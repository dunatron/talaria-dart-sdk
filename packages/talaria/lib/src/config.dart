import 'dart:math';

import 'capture_context.dart';
import 'credential.dart';
import 'fail_safe.dart';
import 'identity/storage.dart';
import 'release_env_stub.dart' if (dart.library.io) 'release_env_io.dart';
import 'release_identity.dart';
import 'severity.dart';

typedef BeforeSendCallback = BeforeSendEvent? Function(
  BeforeSendEvent event,
  BeforeSendHint hint,
);

/// The parsed key and ingest URL, or why Talaria is disabled.
typedef _Resolved = ({
  TalariaCredential? credential,
  String url,
  String apiKey,
  String? reason,
});

/// Immutable SDK configuration.
///
/// Never throws (D19). A missing, empty, malformed or wrong-checksum key, a
/// monitor token, a `self` cell without a url, or a bad option builds a disabled configuration: [enabled] is
/// false, [disabledReason] says why, and the client built from it is a no-op.
class TalariaOptions {
  /// [environment] is accepted so call sites built against 0.3.6 still compile.
  /// The API key decides the environment, so the value is not stored or sent.
  ///
  /// [disabledReason] forces a disabled no-op client (the SDK sets it when
  /// init fails).
  TalariaOptions({
    String? url,
    required String apiKey,
    String? environment,
    String? release,
    String? commitSha,
    double sampleRate = 1.0,
    int maxBatchSize = 50,
    int flushIntervalMs = 2000,
    int spanBatchSize = 200,
    int spanFlushIntervalMs = 5000,
    int maxSpanExportsPerMinute = 30,
    int maxSpanQueueSize = 2048,
    this.defaultIntegrations = true,
    this.userId,
    Map<String, String>? tags,
    double httpTimeoutSeconds = 3.0,
    Object minLevel = SeverityLevel.debug,
    this.enforceDefaultLevel = false,
    Map<String, LoggerPreset>? loggers,
    this.beforeSend,
    List<Pattern>? ignoreErrors,
    List<Pattern>? ignoreUrls,
    this.platform = 'dart',
    this.storage,
    String? disabledReason,
  })  : _inputApiKey = apiKey,
        _inputUrl = url,
        _forcedReason = disabledReason,
        credential = _resolve(
          apiKey: apiKey,
          url: url,
          sampleRate: sampleRate,
          httpTimeoutSeconds: httpTimeoutSeconds,
          forced: disabledReason,
        ).credential,
        url = _resolve(
          apiKey: apiKey,
          url: url,
          sampleRate: sampleRate,
          httpTimeoutSeconds: httpTimeoutSeconds,
          forced: disabledReason,
        ).url,
        apiKey = _resolve(
          apiKey: apiKey,
          url: url,
          sampleRate: sampleRate,
          httpTimeoutSeconds: httpTimeoutSeconds,
          forced: disabledReason,
        ).apiKey,
        disabledReason = _resolve(
          apiKey: apiKey,
          url: url,
          sampleRate: sampleRate,
          httpTimeoutSeconds: httpTimeoutSeconds,
          forced: disabledReason,
        ).reason,
        release = _safeRelease(release, commitSha)?.release,
        commitSha = _safeRelease(release, commitSha)?.commitSha,
        releaseRefKind = _safeRelease(release, commitSha)?.releaseRefKind,
        sampleRate = sampleRate.isFinite ? sampleRate.clamp(0.0, 1.0) : 1.0,
        maxBatchSize = max(1, maxBatchSize),
        flushIntervalMs = max(0, flushIntervalMs),
        spanBatchSize = spanBatchSize.clamp(1, maxSpanBatchSize),
        spanFlushIntervalMs = max(0, spanFlushIntervalMs),
        maxSpanExportsPerMinute = maxSpanExportsPerMinute.clamp(1, 600),
        maxSpanQueueSize = max(
          spanBatchSize.clamp(1, maxSpanBatchSize),
          maxSpanQueueSize,
        ),
        tags = normalizeTags(tags ?? const {}),
        httpTimeoutSeconds =
            httpTimeoutSeconds.isFinite ? max(0.5, httpTimeoutSeconds) : 3.0,
        minLevel = SeverityLevel.tryFromMixed(minLevel) ?? SeverityLevel.debug,
        loggers = Map.unmodifiable(loggers ?? const {}),
        ignoreErrors = List.unmodifiable(ignoreErrors ?? const []),
        ignoreUrls = List.unmodifiable(ignoreUrls ?? const []),
        enableTracing = false,
        tracesSampleRate = null,
        enableAnalytics = false,
        enableFlags = false;

  final String _inputApiKey;
  final String? _inputUrl;
  final String? _forcedReason;

  /// Parsed key. Null when [enabled] is false.
  final TalariaCredential? credential;

  /// Why Talaria is disabled, safe to log (at most 8 key characters), or
  /// null when it is enabled.
  final String? disabledReason;

  /// False when the key is missing or invalid or an option is bad. The
  /// client built from a disabled configuration sends nothing.
  bool get enabled => disabledReason == null;

  /// Ingest URL. Empty when [enabled] is false.
  final String url;

  /// The parsed key. Empty when [enabled] is false.
  final String apiKey;
  final String? release;
  final String? commitSha;

  /// `branch` or `tag` when CI supplied the release.
  final String? releaseRefKind;
  double sampleRate;
  final int maxBatchSize;
  final int flushIntervalMs;

  /// Most spans in one `/v1/spans` batch request (1 to [maxSpanBatchSize]).
  /// A full batch is exported without waiting for [spanFlushIntervalMs].
  final int spanBatchSize;

  /// Longest a finished span waits before it is exported. 0 sends spans only
  /// on a full batch or an explicit flush. With [flushIntervalMs] 0 the SDK
  /// starts no timers, so spans are sent when a batch is due at the next
  /// span, or on an explicit flush.
  final int spanFlushIntervalMs;

  /// Ceiling on automatic span exports a minute (1 to 600). The server's
  /// default per-key limit is 100 span requests a minute. Explicit
  /// `flush()` calls are not limited.
  final int maxSpanExportsPerMinute;

  /// Finished spans held while waiting to export. More are dropped and
  /// reported as `queue_overflow`. At least [spanBatchSize].
  final int maxSpanQueueSize;

  /// The server rejects more than 200 spans of one trace in a batch.
  static const maxSpanBatchSize = 200;
  final bool defaultIntegrations;
  final String? userId;
  final Map<String, String> tags;
  final double httpTimeoutSeconds;
  final SeverityLevel minLevel;
  final bool enforceDefaultLevel;
  final Map<String, LoggerPreset> loggers;
  final BeforeSendCallback? beforeSend;
  final List<Pattern> ignoreErrors;
  final List<Pattern> ignoreUrls;

  /// Wire `platform` field (`dart` or `flutter`).
  final String platform;

  /// Set from the project policy document. Init does not take this flag.
  bool enableTracing;

  /// Head-sample rate for successful transactions once [enableTracing] is on.
  double? tracesSampleRate;

  /// Set from the project policy document. Browser consent is [TalariaAnalytics.optIn].
  bool enableAnalytics;

  /// Set from `flags.enabled` in the project policy document.
  bool enableFlags;

  /// Set from `heatmaps.enabled`. Flutter screen capture reads this.
  bool heatmapsEnabled = false;

  /// Quota pause from `ingest.events.state`. Separate from a permanent kill switch.
  bool eventsPaused = false;

  /// Quota pause from `ingest.transactions.state`.
  bool transactionsPaused = false;

  /// Quota pause from `ingest.analytics.state`.
  bool analyticsPaused = false;

  /// Durable anonymous/session storage. Default is in-memory.
  final TalariaStorage? storage;

  /// Tracing is off until [enableTracing] is true or [tracesSampleRate] `> 0`.
  bool get isTracingEnabled =>
      enableTracing || (tracesSampleRate != null && tracesSampleRate! > 0);

  /// Success-path sample rate once tracing is on. Errors are always 100%.
  double get effectiveTracesSampleRate => tracesSampleRate ?? 0.10;

  void applySdkDocument(Map<String, Object?> document) {
    if (document['schemaVersion'] != null && document['schemaVersion'] != 1) {
      return;
    }
    if (document['unchanged'] == true) return;
    if (document['active'] == false) {
      enableTracing = false;
      tracesSampleRate = 0;
      enableAnalytics = false;
      enableFlags = false;
      heatmapsEnabled = false;
      sampleRate = 0;
      eventsPaused = true;
      transactionsPaused = true;
      analyticsPaused = true;
      return;
    }
    final events = document['events'];
    if (events is Map && events['sampleRate'] is num) {
      sampleRate = (events['sampleRate'] as num).toDouble().clamp(0.0, 1.0);
    }
    final tracing = document['tracing'];
    if (tracing is Map) {
      enableTracing = tracing['enabled'] == true;
      final rate = tracing['tracesSampleRate'];
      tracesSampleRate = enableTracing && rate is num ? rate.toDouble() : 0;
    }
    final analytics = document['analytics'];
    if (analytics is Map) {
      enableAnalytics = analytics['enabled'] == true;
    }
    final flags = document['flags'];
    if (flags is Map) {
      enableFlags = flags['enabled'] == true;
    }
    final heatmaps = document['heatmaps'];
    heatmapsEnabled = heatmaps is Map && heatmaps['enabled'] == true;
    final ingest = document['ingest'];
    if (ingest is Map) {
      eventsPaused = _meterPaused(ingest['events']);
      transactionsPaused = _meterPaused(ingest['transactions']);
      analyticsPaused = _meterPaused(ingest['analytics']);
    } else {
      eventsPaused = false;
      transactionsPaused = false;
      analyticsPaused = false;
    }
  }

  static bool _meterPaused(Object? meter) {
    if (meter is Map) {
      return meter['state'] == 'paused';
    }
    return false;
  }

  bool shouldSample([Random? random]) {
    if (sampleRate >= 1.0) {
      return true;
    }
    if (sampleRate <= 0.0) {
      return false;
    }
    final rng = random ?? Random();
    return rng.nextDouble() <= sampleRate;
  }

  /// Copy with selected overrides. Used by `talaria_flutter` to set platform.
  TalariaOptions copyWith({
    String? url,
    String? apiKey,
    String? release,
    String? commitSha,
    double? sampleRate,
    int? maxBatchSize,
    int? flushIntervalMs,
    int? spanBatchSize,
    int? spanFlushIntervalMs,
    int? maxSpanExportsPerMinute,
    int? maxSpanQueueSize,
    bool? defaultIntegrations,
    String? userId,
    Map<String, String>? tags,
    double? httpTimeoutSeconds,
    Object? minLevel,
    bool? enforceDefaultLevel,
    Map<String, LoggerPreset>? loggers,
    BeforeSendCallback? beforeSend,
    List<Pattern>? ignoreErrors,
    List<Pattern>? ignoreUrls,
    String? platform,
    TalariaStorage? storage,
  }) {
    final created = TalariaOptions(
      url: url ?? _inputUrl,
      apiKey: apiKey ?? _inputApiKey,
      release: release ?? this.release,
      commitSha: commitSha ?? this.commitSha,
      sampleRate: sampleRate ?? this.sampleRate,
      maxBatchSize: maxBatchSize ?? this.maxBatchSize,
      flushIntervalMs: flushIntervalMs ?? this.flushIntervalMs,
      spanBatchSize: spanBatchSize ?? this.spanBatchSize,
      spanFlushIntervalMs: spanFlushIntervalMs ?? this.spanFlushIntervalMs,
      maxSpanExportsPerMinute:
          maxSpanExportsPerMinute ?? this.maxSpanExportsPerMinute,
      maxSpanQueueSize: maxSpanQueueSize ?? this.maxSpanQueueSize,
      defaultIntegrations: defaultIntegrations ?? this.defaultIntegrations,
      userId: userId ?? this.userId,
      tags: tags ?? this.tags,
      httpTimeoutSeconds: httpTimeoutSeconds ?? this.httpTimeoutSeconds,
      minLevel: minLevel ?? this.minLevel,
      enforceDefaultLevel: enforceDefaultLevel ?? this.enforceDefaultLevel,
      loggers: loggers ?? this.loggers,
      beforeSend: beforeSend ?? this.beforeSend,
      ignoreErrors: ignoreErrors ?? this.ignoreErrors,
      ignoreUrls: ignoreUrls ?? this.ignoreUrls,
      platform: platform ?? this.platform,
      storage: storage ?? this.storage,
      disabledReason: _forcedReason,
    );
    created.enableTracing = enableTracing;
    created.tracesSampleRate = tracesSampleRate;
    created.enableAnalytics = enableAnalytics;
    created.enableFlags = enableFlags;
    created.heatmapsEnabled = heatmapsEnabled;
    created.sampleRate = sampleRate ?? this.sampleRate;
    created.eventsPaused = eventsPaused;
    created.transactionsPaused = transactionsPaused;
    created.analyticsPaused = analyticsPaused;
    return created;
  }

  static const definedUrl = String.fromEnvironment('TALARIA_URL');

  /// Parse the key and resolve the URL. Never throws (D19).
  static _Resolved _resolve({
    required String apiKey,
    required String? url,
    required double sampleRate,
    required double httpTimeoutSeconds,
    String? forced,
  }) {
    _Resolved off(String reason) =>
        (credential: null, url: '', apiKey: '', reason: reason);
    if (forced != null) return off(forced);
    final preview = FailSafe.keyPreview(apiKey);
    final named = preview.isEmpty ? 'The API key' : 'The API key ($preview)';
    try {
      if (apiKey.trim().isEmpty) {
        return off('no API key is set (pass apiKey, e.g. '
            '--dart-define=TALARIA_API_KEY)');
      }
      if (!sampleRate.isFinite) {
        return off('the sampleRate option is not a finite number');
      }
      if (!httpTimeoutSeconds.isFinite) {
        return off('the httpTimeoutSeconds option is not a finite number');
      }
      final TalariaCredential credential;
      try {
        credential = TalariaCredential.parse(apiKey);
      } on ArgumentError catch (e) {
        return off('$named is invalid: ${e.message}');
      }
      if (credential.isMonitor) {
        return off('$named is a tal_mon_ token, which is only valid for '
            'POST /v1/check-ins. Use a tal_pk_ or tal_sk_ key');
      }
      final resolvedUrl = _resolveUrl(url: url, credential: credential);
      if (resolvedUrl == null) {
        return off('$named has a self cell and no url. Set TALARIA_URL or '
            'the url option');
      }
      return (
        credential: credential,
        url: resolvedUrl,
        apiKey: credential.value,
        reason: null,
      );
    } catch (e) {
      return off('init failed ($e)');
    }
  }

  static ReleaseIdentity? _safeRelease(String? release, String? commitSha) {
    try {
      return ReleaseIdentity.resolve(release: release, commitSha: commitSha);
    } catch (_) {
      return null;
    }
  }

  /// Explicit [url], then `TALARIA_URL` (`--dart-define` or the process
  /// environment), then `https://ingest-<cell>.newtalaria.com`. Null for a
  /// `self` cell with no override.
  static String? _resolveUrl({
    String? url,
    required TalariaCredential credential,
    Map<String, String>? env,
  }) {
    final explicit = _nonEmpty(url);
    if (explicit != null) return explicit;
    final fromDefine = _nonEmpty(definedUrl);
    if (fromDefine != null) return fromDefine;
    final fromEnv = _nonEmpty((env ?? releaseEnvironment())['TALARIA_URL']);
    if (fromEnv != null) return fromEnv;
    if (credential.isSelfCell) return null;
    return credential.derivedIngestUrl;
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  static Map<String, String> normalizeTags(Map<String, Object?> tags) {
    final normalized = <String, String>{};
    for (final entry in tags.entries) {
      if (entry.key.isEmpty) {
        continue;
      }
      final value = entry.value;
      if (value == null) {
        continue;
      }
      normalized[entry.key] = value.toString();
    }
    return normalized;
  }
}

/// Mutable alias used by the client after init.
typedef Config = TalariaOptions;
