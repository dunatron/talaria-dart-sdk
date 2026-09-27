import 'dart:math';

import 'capture_context.dart';
import 'environment.dart';
import 'identity/storage.dart';
import 'severity.dart';

typedef BeforeSendCallback = BeforeSendEvent? Function(
  BeforeSendEvent event,
  BeforeSendHint hint,
);

/// Immutable SDK configuration.
class TalariaOptions {
  TalariaOptions({
    String? dsn,
    String? baseUrl,
    required this.apiKey,
    required Object environment,
    this.release,
    this.commitSha,
    double sampleRate = 1.0,
    int maxBatchSize = 50,
    int flushIntervalMs = 2000,
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
  })  : baseUrl = _resolveBaseUrl(dsn: dsn, baseUrl: baseUrl),
        environment = Environment.fromMixed(environment),
        sampleRate = sampleRate.clamp(0.0, 1.0),
        maxBatchSize = max(1, maxBatchSize),
        flushIntervalMs = max(0, flushIntervalMs),
        tags = normalizeTags(tags ?? const {}),
        httpTimeoutSeconds = max(0.5, httpTimeoutSeconds),
        minLevel = SeverityLevel.tryFromMixed(minLevel) ?? SeverityLevel.debug,
        loggers = Map.unmodifiable(loggers ?? const {}),
        ignoreErrors = List.unmodifiable(ignoreErrors ?? const []),
        ignoreUrls = List.unmodifiable(ignoreUrls ?? const []),
        enableTracing = false,
        tracesSampleRate = null,
        enableAnalytics = false {
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw ArgumentError('Talaria init requires apiKey.');
    }
    if (!key.startsWith('tal_live_')) {
      throw ArgumentError('Talaria apiKey must start with tal_live_.');
    }
  }

  final String baseUrl;
  final String apiKey;
  final Environment environment;
  final String? release;
  final String? commitSha;
  double sampleRate;
  final int maxBatchSize;
  final int flushIntervalMs;
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
      sampleRate = 0;
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
    String? dsn,
    String? baseUrl,
    String? apiKey,
    Object? environment,
    String? release,
    String? commitSha,
    double? sampleRate,
    int? maxBatchSize,
    int? flushIntervalMs,
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
      dsn: dsn,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      environment: environment ?? this.environment,
      release: release ?? this.release,
      commitSha: commitSha ?? this.commitSha,
      sampleRate: sampleRate ?? this.sampleRate,
      maxBatchSize: maxBatchSize ?? this.maxBatchSize,
      flushIntervalMs: flushIntervalMs ?? this.flushIntervalMs,
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
    );
    created.enableTracing = enableTracing;
    created.tracesSampleRate = tracesSampleRate;
    created.enableAnalytics = enableAnalytics;
    created.sampleRate = sampleRate ?? this.sampleRate;
    return created;
  }

  static String _resolveBaseUrl({String? dsn, String? baseUrl}) {
    final raw = (dsn ?? baseUrl)?.trim();
    if (raw == null || raw.isEmpty) {
      throw ArgumentError('Talaria init requires dsn or baseUrl.');
    }
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
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
