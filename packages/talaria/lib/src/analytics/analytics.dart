import 'dart:convert';
import 'dart:developer' as developer;

import '../context/runtime_context.dart';
import '../identity/identity.dart';
import '../identity/utm.dart';
import '../tracing/span.dart';
import '../transport/analytics_queue.dart';
import 'analytics_event.dart';

/// Product analytics API (`track` / `page` / `screen` / `identify`).
///
/// Consent is **off** until [TalariaOptions.enableAnalytics] or [optIn].
/// Server Dart (non-Flutter) requires the caller to pass `userId` and/or
/// `anonymousId` (or set them on the client / zone) so process-wide ids are
/// not mixed across requests.
class TalariaAnalytics {
  TalariaAnalytics({
    required Identity identity,
    required AnalyticsQueue queue,
    required bool enabled,
    required bool Function() isDisabled,
    required bool Function() isClosed,
    required bool Function() isFlutter,
    required String Function() platform,
    required String Function() environment,
    required String? Function() release,
    required String? Function() userId,
    required void Function(String? userId) setUser,
    required Span? Function() currentSpan,
    required String? Function() requestId,
    this.contextProvider,
  })  : _identity = identity,
        _queue = queue,
        _enabled = enabled,
        _isDisabled = isDisabled,
        _isClosed = isClosed,
        _isFlutter = isFlutter,
        _platform = platform,
        _environment = environment,
        _release = release,
        _userId = userId,
        _setUser = setUser,
        _currentSpan = currentSpan,
        _requestId = requestId;

  final Identity _identity;
  final AnalyticsQueue _queue;
  bool _enabled;
  final bool Function() _isDisabled;
  final bool Function() _isClosed;
  final bool Function() _isFlutter;
  final String Function() _platform;
  final String Function() _environment;
  final String? Function() _release;
  final String? Function() _userId;
  final void Function(String? userId) _setUser;
  final Span? Function() _currentSpan;
  final String? Function() _requestId;

  /// Optional host page fields (Flutter web location).
  AnalyticsContextProvider? contextProvider;

  bool get isEnabled => _enabled && !_isDisabled() && !_isClosed();

  void optIn() {
    _enabled = true;
  }

  void optOut() {
    _enabled = false;
  }

  /// Bind [userId] and emit `$identify` when analytics is on.
  Future<void> identify(
    String userId, {
    Map<String, Object?>? traits,
    String? anonymousId,
    String? sessionId,
    String? name,
  }) async {
    final trimmed = userId.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _setUser(trimmed);
    await _enqueue(
      name: (name != null && name.trim().isNotEmpty)
          ? name.trim()
          : AnalyticsEventNames.identify,
      kind: AnalyticsEventKind.identify,
      properties: traits,
      userId: trimmed,
      anonymousId: anonymousId,
      sessionId: sessionId,
    );
  }

  Future<void> track(
    String name, {
    Map<String, Object?>? properties,
    String? userId,
    String? anonymousId,
    String? sessionId,
    String? url,
    String? path,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await _enqueue(
      name: trimmed,
      kind: AnalyticsEventKind.track,
      properties: properties,
      userId: userId,
      anonymousId: anonymousId,
      sessionId: sessionId,
      url: url,
      path: path,
    );
  }

  Future<void> page({
    String? name,
    String? url,
    String? path,
    String? title,
    String? referrer,
    Map<String, Object?>? properties,
    String? userId,
    String? anonymousId,
    String? sessionId,
  }) async {
    final page = _pageContext();
    await _enqueue(
      name: (name != null && name.trim().isNotEmpty)
          ? name.trim()
          : AnalyticsEventNames.pageview,
      kind: AnalyticsEventKind.page,
      properties: properties,
      userId: userId,
      anonymousId: anonymousId,
      sessionId: sessionId,
      url: url ?? page?.url,
      path: path ?? page?.path,
      title: title ?? page?.title,
      referrer: referrer ?? page?.referrer,
    );
  }

  Future<void> screen({
    String? name,
    String? path,
    String? title,
    Map<String, Object?>? properties,
    String? userId,
    String? anonymousId,
    String? sessionId,
  }) async {
    final page = _pageContext();
    await _enqueue(
      name: (name != null && name.trim().isNotEmpty)
          ? name.trim()
          : AnalyticsEventNames.screen,
      kind: AnalyticsEventKind.screen,
      properties: properties,
      userId: userId,
      anonymousId: anonymousId,
      sessionId: sessionId,
      path: path ?? page?.path ?? RuntimeContext.url,
      title: title ?? page?.title,
      url: page?.url ?? RuntimeContext.url,
    );
  }

  /// New anonymousId + session; clear the identified user. Does not opt out.
  Future<void> reset() async {
    _setUser(null);
    await _identity.reset();
  }

  AnalyticsPageContext? _pageContext() {
    try {
      return contextProvider?.call();
    } catch (e, st) {
      developer.log(
        '[Talaria] analytics context provider failed: $e',
        name: 'talaria',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  Future<void> _enqueue({
    required String name,
    required AnalyticsEventKind kind,
    Map<String, Object?>? properties,
    String? userId,
    String? anonymousId,
    String? sessionId,
    String? url,
    String? path,
    String? title,
    String? referrer,
  }) async {
    if (!_enabled || _isDisabled() || _isClosed()) {
      return;
    }

    final resolvedUserId = _nonEmpty(userId) ??
        _nonEmpty(RuntimeContext.userId) ??
        _nonEmpty(_userId());
    final resolvedAnonymousId = _nonEmpty(anonymousId) ??
        _nonEmpty(RuntimeContext.anonymousId) ??
        (_isFlutter() ? _identity.anonymousId : null);

    if (!_isFlutter()) {
      final hasCallerIdentity = resolvedUserId != null ||
          _nonEmpty(anonymousId) != null ||
          _nonEmpty(RuntimeContext.anonymousId) != null;
      if (!hasCallerIdentity) {
        return;
      }
    }

    final anonymous = resolvedAnonymousId ?? _identity.anonymousId;
    if (anonymous.isEmpty) {
      return;
    }

    _identity.touch();
    final page = _pageContext();
    final resolvedUrl = Utm.sanitizeUrl(
      url ?? page?.url ?? RuntimeContext.url,
    );
    _identity.captureUtmFromUrl(resolvedUrl);
    final utm = _identity.firstTouchUtm;

    String? traceId;
    String? spanId;
    final span = _currentSpan();
    if (span != null && span.isRecording) {
      traceId = span.traceId;
      spanId = span.spanId;
    }

    _queue.enqueue(
      AnalyticsEvent(
        eventId: RuntimeContext.newUuid(),
        name: name,
        kind: kind,
        anonymousId: anonymous,
        sessionId: _nonEmpty(sessionId) ??
            _nonEmpty(RuntimeContext.sessionId) ??
            _identity.sessionId,
        timestamp: DateTime.now().toUtc(),
        userId: resolvedUserId,
        replayId: RuntimeContext.replayId,
        traceId: traceId,
        spanId: spanId,
        requestId: _requestId(),
        platform: _platform(),
        environment: _environment(),
        release: _release(),
        url: resolvedUrl,
        path: _nonEmpty(path) ?? page?.path,
        title: _nonEmpty(title) ?? page?.title,
        referrer: Utm.sanitizeUrl(referrer ?? page?.referrer),
        utmSource: utm?.source,
        utmMedium: utm?.medium,
        utmCampaign: utm?.campaign,
        utmTerm: utm?.term,
        utmContent: utm?.content,
        propertiesJson: _encodeProperties(properties),
      ),
    );
  }

  static String? _nonEmpty(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _encodeProperties(Map<String, Object?>? properties) {
    if (properties == null || properties.isEmpty) {
      return null;
    }
    try {
      return jsonEncode(properties);
    } catch (_) {
      return null;
    }
  }
}
