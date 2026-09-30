import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import '../analytics/analytics.dart';
import '../analytics/analytics_event.dart';
import '../config.dart';
import '../identity/identity.dart';
import '../identity/storage.dart';
import 'flag_definition.dart';
import 'flag_evaluation.dart';
import 'local_flag_evaluator.dart';

/// Feature-flag client (`POST /flags/evaluate` or local definitions).
///
/// Typed variation helpers always take a required default. When policy
/// `flags.enabled` is off, network is skipped and defaults are returned.
/// Disk cache (via [TalariaStorage]) and a start timeout keep cold starts
/// from blocking the UI.
///
/// Call [loadDefinitions] (requires `flags:definitions` on the API key) to
/// switch to local evaluation — preferred for server Dart / Serverpod so
/// mid-request reads do not RTT. Mobile / browser clients should stay on
/// remote evaluate; poll refreshes while foregrounded — backgrounded apps
/// may not update until they resume.
class TalariaFlags {
  TalariaFlags({
    required TalariaOptions options,
    required Identity identity,
    required TalariaStorage storage,
    required Future<Map<String, Object?>> Function(Map<String, Object?> input)
        evaluate,
    Future<Map<String, Object?>> Function(Map<String, Object?> input)?
        downloadDefinitions,
    required String? Function() userId,
    TalariaAnalytics? analytics,
    this.startTimeout = const Duration(seconds: 3),
    Duration pollInterval = const Duration(seconds: 60),
    void Function(Map<String, FlagEvaluationResult> flags)? onFlagsChanged,
    LocalFlagEvaluator evaluator = const LocalFlagEvaluator(),
  })  : _options = options,
        _identity = identity,
        _storage = storage,
        _evaluate = evaluate,
        _downloadDefinitions = downloadDefinitions,
        _userId = userId,
        _analytics = analytics,
        _pollInterval = pollInterval,
        _onFlagsChanged = onFlagsChanged,
        _evaluator = evaluator {
    _loadCacheForCurrentContext();
  }

  static const cacheKeyPrefix = 'talaria.flags.cache.';
  static const definitionsCacheKeyPrefix = 'talaria.flags.definitions.';
  static const maxStampFlags = 20;

  final TalariaOptions _options;
  final Identity _identity;
  final TalariaStorage _storage;
  final Future<Map<String, Object?>> Function(Map<String, Object?> input)
      _evaluate;
  final Future<Map<String, Object?>> Function(Map<String, Object?> input)?
      _downloadDefinitions;
  final String? Function() _userId;
  final TalariaAnalytics? _analytics;
  final void Function(Map<String, FlagEvaluationResult> flags)?
      _onFlagsChanged;
  final LocalFlagEvaluator _evaluator;

  Duration startTimeout;
  Duration _pollInterval;

  static const Object _unset = Object();

  String? _contextUserId;
  String? _organizationId;
  Map<String, String> _attributes = const {};
  Map<String, FlagEvaluationResult> _evaluations = {};
  List<FlagDefinition> _definitions = const [];
  bool _localMode = false;
  String? _fingerprint;
  Completer<void>? _inFlight;
  Timer? _pollTimer;
  bool _closed = false;
  final Set<String> _calledThisSession = {};
  final StreamController<Map<String, FlagEvaluationResult>> _changes =
      StreamController<Map<String, FlagEvaluationResult>>.broadcast();

  /// True after a successful [loadDefinitions].
  bool get isLocalMode => _localMode;

  /// Last evaluation map (key → result). Empty until cache or network.
  Map<String, FlagEvaluationResult> get evaluatedMap =>
      Map.unmodifiable(_evaluations);

  /// Compact stamp map: `flag key → variationKey` (capped for outbound tags).
  Map<String, String> get activeFlags {
    final out = <String, String>{};
    for (final entry in _evaluations.entries) {
      if (out.length >= maxStampFlags) break;
      final variation = entry.value.variationKey;
      if (variation.isEmpty) continue;
      out[entry.key] = variation;
    }
    return Map.unmodifiable(out);
  }

  /// Tags suitable for events / span attributes: `flag.<key> → variation`.
  Map<String, String> stampTags({int max = maxStampFlags}) {
    final out = <String, String>{};
    for (final entry in activeFlags.entries) {
      if (out.length >= max) break;
      out['flag.${entry.key}'] = entry.value;
    }
    return out;
  }

  Stream<Map<String, FlagEvaluationResult>> get changes => _changes.stream;

  /// Update targeting context and reload evaluations.
  ///
  /// Pass `userId: null` / `organizationId: null` to clear those fields.
  Future<void> setContext({
    Object? userId = _unset,
    Object? organizationId = _unset,
    Map<String, String>? attributes,
  }) async {
    if (!identical(userId, _unset)) {
      final raw = userId as String?;
      _contextUserId =
          (raw != null && raw.trim().isNotEmpty) ? raw.trim() : null;
    }
    if (!identical(organizationId, _unset)) {
      final raw = organizationId as String?;
      _organizationId =
          (raw != null && raw.trim().isNotEmpty) ? raw.trim() : null;
    }
    if (attributes != null) {
      _attributes = Map.unmodifiable(
        attributes.map((k, v) => MapEntry(k, v.toString())),
      );
    }
    _loadCacheForCurrentContext();
    await reload();
  }

  /// Download definitions and switch to local evaluation.
  ///
  /// Requires API key scope `flags:definitions` (server/backend keys only).
  Future<void> loadDefinitions({List<String>? keys}) async {
    if (_closed || !_options.enableFlags) return;
    final download = _downloadDefinitions;
    if (download == null) {
      throw StateError('Transport does not support downloadDefinitions');
    }
    final raw = await download({
      if (keys != null && keys.isNotEmpty) 'keys': keys,
    });
    final defs = parseFlagDefinitions(raw);
    _definitions = defs;
    _localMode = true;
    await _persistDefinitionsCache();
    _applyLocalEvaluations();
  }

  /// Force a network evaluate (or definition refresh in local mode).
  Future<void> reload() async {
    if (_closed || !_options.enableFlags) {
      return;
    }
    await _refresh(wait: true);
  }

  /// Policy / TTL hook from [TalariaClient] after `getConfig`.
  void onPolicyUpdated({Duration? pollInterval}) {
    if (pollInterval != null) {
      _pollInterval = pollInterval;
    }
    if (!_options.enableFlags) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    _loadCacheForCurrentContext();
    unawaited(_refresh(wait: false));
    _schedulePoll();
  }

  Future<bool> boolVariation(String key, bool defaultValue) async {
    final result = await _resolve(key);
    if (result == null) return defaultValue;
    await _maybeTrackCalled(key, result);
    final value = result.value;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final lower = value.toLowerCase();
      if (lower == 'true' || lower == '1') return true;
      if (lower == 'false' || lower == '0') return false;
    }
    return defaultValue;
  }

  Future<String> stringVariation(String key, String defaultValue) async {
    final result = await _resolve(key);
    if (result == null) return defaultValue;
    await _maybeTrackCalled(key, result);
    final value = result.value;
    if (value == null) return defaultValue;
    if (value is String) return value;
    return value.toString();
  }

  Future<Object?> jsonVariation(String key, Object? defaultValue) async {
    final result = await _resolve(key);
    if (result == null) return defaultValue;
    await _maybeTrackCalled(key, result);
    return result.value ?? defaultValue;
  }

  Future<FlagEvaluationResult?> evaluation(String key) async {
    return _resolve(key);
  }

  void close() {
    _closed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    if (!_changes.isClosed) {
      _changes.close();
    }
  }

  Future<FlagEvaluationResult?> _resolve(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return null;

    if (!_options.enableFlags) {
      return null;
    }

    final cached = _evaluations[trimmed];
    if (cached != null) return cached;

    // Wait briefly for the first fetch when we have nothing yet.
    if (_inFlight != null || _evaluations.isEmpty) {
      await _ensureStarted();
    }

    return _evaluations[trimmed];
  }

  Future<void> _ensureStarted() async {
    if (_closed || !_options.enableFlags) return;
    final existing = _inFlight;
    if (existing != null) {
      try {
        await existing.future.timeout(startTimeout);
      } catch (_) {}
      return;
    }
    final started = _refresh(wait: true);
    try {
      await started.timeout(startTimeout);
    } catch (_) {}
  }

  Future<void> _refresh({required bool wait}) async {
    if (_closed || !_options.enableFlags) return;

    if (_inFlight != null) {
      if (wait) await _inFlight!.future;
      return;
    }

    final completer = Completer<void>();
    _inFlight = completer;
    try {
      if (_localMode) {
        await _refreshLocal();
      } else {
        await _refreshRemote();
      }
    } catch (e, st) {
      developer.log(
        '[Talaria] flags refresh failed: $e',
        name: 'talaria',
        error: e,
        stackTrace: st,
      );
    } finally {
      completer.complete();
      if (identical(_inFlight, completer)) {
        _inFlight = null;
      }
    }
  }

  Future<void> _refreshRemote() async {
    final input = <String, Object?>{
      'anonymousId': _identity.anonymousId,
      if (_effectiveUserId() != null) 'userId': _effectiveUserId(),
      if (_organizationId != null) 'organizationId': _organizationId,
      if (_attributes.isNotEmpty) 'attributes': _attributes,
    };
    final raw = await _evaluate(input);
    final list = _parseEvaluations(raw);
    final next = <String, FlagEvaluationResult>{
      for (final item in list)
        if (item.key.isNotEmpty) item.key: item,
    };
    _applyEvaluations(next);
  }

  Future<void> _refreshLocal() async {
    final download = _downloadDefinitions;
    if (download != null) {
      try {
        final raw = await download(const {});
        final defs = parseFlagDefinitions(raw);
        if (defs.isNotEmpty) {
          _definitions = defs;
          await _persistDefinitionsCache();
        }
      } catch (e, st) {
        developer.log(
          '[Talaria] flags definition refresh failed: $e',
          name: 'talaria',
          error: e,
          stackTrace: st,
        );
      }
    }
    _applyLocalEvaluations();
  }

  void _applyLocalEvaluations() {
    final context = LocalFlagContext(
      anonymousId: _identity.anonymousId,
      userId: _effectiveUserId(),
      organizationId: _organizationId,
      attributes: _attributes,
    );
    final list = _evaluator.evaluateAll(_definitions, context);
    final next = <String, FlagEvaluationResult>{
      for (final item in list)
        if (item.key.isNotEmpty) item.key: item,
    };
    _applyEvaluations(next);
  }

  void _applyEvaluations(Map<String, FlagEvaluationResult> next) {
    _evaluations = next;
    _fingerprint = _contextFingerprint();
    unawaited(_persistCache());
    if (!_changes.isClosed) {
      _changes.add(Map.unmodifiable(next));
    }
    _onFlagsChanged?.call(Map.unmodifiable(next));
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    if (_closed || !_options.enableFlags) return;
    final wait = _pollInterval.inMilliseconds.clamp(15 * 1000, 60 * 60 * 1000);
    _pollTimer = Timer(Duration(milliseconds: wait), () {
      unawaited(() async {
        await _refresh(wait: false);
        _schedulePoll();
      }());
    });
  }

  String? _effectiveUserId() {
    final fromContext = _contextUserId;
    if (fromContext != null && fromContext.isNotEmpty) {
      return fromContext;
    }
    final fromGetter = _userId();
    if (fromGetter != null && fromGetter.trim().isNotEmpty) {
      return fromGetter.trim();
    }
    return null;
  }

  String _contextFingerprint() {
    final attrs = _attributes.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final attrPart = attrs.map((e) => '${e.key}=${e.value}').join('&');
    return [
      _identity.anonymousId,
      _effectiveUserId() ?? '',
      _organizationId ?? '',
      attrPart,
      if (_localMode) 'local',
    ].join('|');
  }

  String _cacheStorageKey() =>
      '$cacheKeyPrefix${_options.apiKey.hashCode.toRadixString(16)}';

  String _definitionsStorageKey() =>
      '$definitionsCacheKeyPrefix${_options.apiKey.hashCode.toRadixString(16)}';

  void _loadCacheForCurrentContext() {
    _loadDefinitionsCache();
    final raw = _storage.read(_cacheStorageKey());
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = decoded.map((k, v) => MapEntry(k.toString(), v));
      final fingerprint = map['fingerprint'] as String?;
      if (fingerprint != _contextFingerprint()) return;
      final list = map['evaluations'];
      if (list is! List) return;
      final next = <String, FlagEvaluationResult>{};
      for (final item in list) {
        if (item is! Map) continue;
        final result = FlagEvaluationResult.fromWire(
          item.map((k, v) => MapEntry(k.toString(), v)),
        );
        if (result.key.isEmpty) continue;
        next[result.key] = result;
      }
      _evaluations = next;
      _fingerprint = fingerprint;
    } catch (_) {}
  }

  void _loadDefinitionsCache() {
    final raw = _storage.read(_definitionsStorageKey());
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final defs = parseFlagDefinitions(
        decoded.map((k, v) => MapEntry(k.toString(), v)),
      );
      if (defs.isEmpty) return;
      _definitions = defs;
      _localMode = true;
    } catch (_) {}
  }

  Future<void> _persistCache() async {
    final fingerprint = _fingerprint ?? _contextFingerprint();
    final payload = jsonEncode({
      'fingerprint': fingerprint,
      'evaluations': [
        for (final item in _evaluations.values) item.toCacheJson(),
      ],
    });
    try {
      await _storage.write(_cacheStorageKey(), payload);
    } catch (_) {}
  }

  Future<void> _persistDefinitionsCache() async {
    try {
      await _storage.write(
        _definitionsStorageKey(),
        encodeFlagDefinitionsCache(_definitions),
      );
    } catch (_) {}
  }

  List<FlagEvaluationResult> _parseEvaluations(Map<String, Object?> raw) {
    final list = raw['evaluations'] ?? raw['flags'];
    if (list is! List) return const [];
    final out = <FlagEvaluationResult>[];
    for (final item in list) {
      if (item is! Map) continue;
      final result = FlagEvaluationResult.fromWire(
        item.map((k, v) => MapEntry(k.toString(), v)),
      );
      if (result.key.isEmpty) continue;
      out.add(result);
    }
    return out;
  }

  Future<void> _maybeTrackCalled(
    String key,
    FlagEvaluationResult result,
  ) async {
    if (_calledThisSession.contains(key)) return;
    _calledThisSession.add(key);
    final analytics = _analytics;
    if (analytics == null || !analytics.isEnabled) return;
    await analytics.track(
      AnalyticsEventNames.featureFlagCalled,
      properties: {
        r'$feature_flag': key,
        r'$feature_flag_response': result.variationKey,
        'version': result.version,
        if (result.reason != null) 'reason': result.reason,
      },
      userId: _effectiveUserId(),
      anonymousId: _identity.anonymousId,
    );
  }
}
