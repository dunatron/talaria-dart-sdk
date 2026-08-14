import 'dart:math';

import 'capture_context.dart';
import 'environment.dart';
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
    this.platform = 'dart',
    this.enableTracing = false,
    double? tracesSampleRate,
  })  : baseUrl = _resolveBaseUrl(dsn: dsn, baseUrl: baseUrl),
        environment = Environment.fromMixed(environment),
        sampleRate = sampleRate.clamp(0.0, 1.0),
        maxBatchSize = max(1, maxBatchSize),
        flushIntervalMs = max(0, flushIntervalMs),
        tags = normalizeTags(tags ?? const {}),
        httpTimeoutSeconds = max(0.5, httpTimeoutSeconds),
        minLevel = SeverityLevel.tryFromMixed(minLevel) ?? SeverityLevel.debug,
        loggers = Map.unmodifiable(loggers ?? const {}),
        tracesSampleRate = tracesSampleRate?.clamp(0.0, 1.0) {
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
  final double sampleRate;
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

  /// Wire `platform` field (`dart` or `flutter`).
  final String platform;

  /// When true, tracing is on at [effectiveTracesSampleRate] (default 10%).
  final bool enableTracing;

  /// Head-sample rate for **successful** transactions. `null` means 0.10 once
  /// tracing is enabled. Setting a value `> 0` also turns tracing on.
  final double? tracesSampleRate;

  /// Tracing is off until [enableTracing] is true or [tracesSampleRate] `> 0`.
  bool get isTracingEnabled =>
      enableTracing || (tracesSampleRate != null && tracesSampleRate! > 0);

  /// Success-path sample rate once tracing is on. Errors are always 100%.
  double get effectiveTracesSampleRate => tracesSampleRate ?? 0.10;

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
    String? platform,
    bool? enableTracing,
    double? tracesSampleRate,
  }) {
    return TalariaOptions(
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
      platform: platform ?? this.platform,
      enableTracing: enableTracing ?? this.enableTracing,
      tracesSampleRate: tracesSampleRate ?? this.tracesSampleRate,
    );
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
