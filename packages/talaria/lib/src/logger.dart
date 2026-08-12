import 'capture_context.dart';
import 'client.dart';
import 'severity.dart';

/// Scoped Talaria capture facade (queued, not sent immediately).
///
/// Level inheritance (Logback / MEL style):
/// - Unset scope → client [TalariaClient.getMinLevel] (default/root)
/// - Explicit scope `minLevel` replaces the default (may be lower or higher)
/// - When client `enforceDefaultLevel` is true, effective level is
///   max(client.minLevel, assigned)
class TalariaLogger {
  TalariaLogger(this._client, LoggerOptions options)
      : _scopeTags = Map<String, String>.from(options.tags ?? const {}),
        _scopeMinLevel = options.minLevel;

  final TalariaClient _client;
  final Map<String, String> _scopeTags;
  final SeverityLevel? _scopeMinLevel;

  Future<void> debug(String message, {CaptureContext? context}) =>
      log(SeverityLevel.debug, message, context: context);

  Future<void> info(String message, {CaptureContext? context}) =>
      log(SeverityLevel.info, message, context: context);

  Future<void> warning(String message, {CaptureContext? context}) =>
      log(SeverityLevel.warning, message, context: context);

  Future<void> warn(String message, {CaptureContext? context}) =>
      warning(message, context: context);

  Future<void> error(String message, {CaptureContext? context}) =>
      log(SeverityLevel.error, message, context: context);

  Future<void> fatal(String message, {CaptureContext? context}) =>
      log(SeverityLevel.fatal, message, context: context);

  Future<void> log(
    Object level,
    String message, {
    CaptureContext? context,
  }) async {
    final severity = SeverityLevel.tryFromMixed(level) ?? SeverityLevel.info;
    if (!severity.atLeast(effectiveMinLevel())) {
      return;
    }
    await _client.captureMessageFromLogger(
      message,
      level: severity,
      context: _mergeContext(context),
    );
  }

  Future<void> captureMessage(
    String message, {
    Object level = SeverityLevel.info,
    CaptureContext? context,
  }) async {
    final severity = SeverityLevel.tryFromMixed(level) ?? SeverityLevel.info;
    if (!severity.atLeast(effectiveMinLevel())) {
      return;
    }
    await _client.captureMessageFromLogger(
      message,
      level: severity,
      context: _mergeContext(context),
    );
  }

  Future<void> captureException(
    Object error, {
    StackTrace? stackTrace,
    CaptureContext? context,
  }) async {
    if (!SeverityLevel.error.atLeast(effectiveMinLevel())) {
      return;
    }
    await _client.captureExceptionFromLogger(
      error,
      stackTrace: stackTrace,
      context: _mergeContext(context),
    );
  }

  TalariaLogger withTags(Map<String, String> tags) {
    return TalariaLogger(
      _client,
      LoggerOptions(
        tags: {..._scopeTags, ...tags},
        minLevel: _scopeMinLevel,
      ),
    );
  }

  /// Assign a scope minimum level (replaces parent; may raise or lower).
  TalariaLogger withMinLevel(Object minLevel) {
    final next = SeverityLevel.tryFromMixed(minLevel);
    if (next == null) {
      return this;
    }
    return TalariaLogger(
      _client,
      LoggerOptions(
        tags: _scopeTags,
        minLevel: next,
      ),
    );
  }

  TalariaLogger child({
    Map<String, String>? tags,
    Object? minLevel,
  }) {
    var logger = this;
    if (tags != null) {
      logger = logger.withTags(tags);
    }
    if (minLevel != null) {
      logger = logger.withMinLevel(minLevel);
    }
    return logger;
  }

  bool isLevelEnabled(Object level) {
    final severity = SeverityLevel.tryFromMixed(level) ?? SeverityLevel.info;
    return severity.atLeast(effectiveMinLevel());
  }

  SeverityLevel getMinLevel() => effectiveMinLevel();

  SeverityLevel effectiveMinLevel() {
    final assigned = _scopeMinLevel ?? _client.getMinLevel();
    if (_client.isEnforceDefaultLevel()) {
      return SeverityLevel.max(_client.getMinLevel(), assigned);
    }
    return assigned;
  }

  CaptureContext _mergeContext(CaptureContext? context) {
    return CaptureContext(
      tags: {
        ..._scopeTags,
        ...?context?.tags,
      },
      extra: context?.extra,
      userId: context?.userId,
      title: context?.title,
      mechanism: context?.mechanism,
    );
  }
}
