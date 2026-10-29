import '../analytics/analytics_event.dart';
import '../event.dart';
import '../tracing/span.dart';
import 'discards.dart';

/// Sends a batch of events to Talaria ingest.
abstract class Transport {
  Future<void> sendBatch(List<Event> events);

  /// Span ingest. Default is a no-op so event-only fakes keep compiling.
  Future<void> sendSpanBatch(List<FinishedSpan> spans) async {}

  /// Analytics ingest. Default is a no-op so event-only fakes keep compiling.
  Future<void> sendAnalyticsBatch(List<AnalyticsEvent> events) async {}

  /// Flutter screen heatmaps. Default is a no-op.
  Future<Map<String, Object?>> sendScreenHeatmapBatch(
    List<Map<String, Object?>> screenViews,
  ) async => const {};

  /// Fold snapshot plus tiles. Default is a no-op.
  Future<void> uploadScreenHeatmapSnapshot(Map<String, Object?> input) async {}

  /// Masked filmstrip. Default is a no-op.
  Future<void> uploadScreenHeatmapRecording(Map<String, Object?> input) async {}

  /// Hourly discard telemetry. Default is a no-op.
  Future<void> reportDiscards(List<DiscardRow> discards) async {}

  /// Feature flag evaluate. Default is empty (no flags).
  Future<Map<String, Object?>> evaluateFlags(
    Map<String, Object?> input,
  ) async => const {};

  /// Download flag definitions for local evaluation (`flags:definitions`).
  Future<Map<String, Object?>> downloadFlagDefinitions(
    Map<String, Object?> input,
  ) async => const {};
}

/// Raised when ingest HTTP fails.
class TransportException implements Exception {
  TransportException(
    this.message, {
    this.statusCode,
    this.cause,
    this.className,
    this.retry,
    this.bodyMessage,
    this.retryAfter,
    this.resetAt,
    this.meter,
  });

  final String message;
  final int? statusCode;
  final Object? cause;

  /// Serverpod exception class from the body (`ApiUnauthorizedException`, …).
  final String? className;

  /// Wire `retry` flag. `false` means the credential/project will not recover.
  final bool? retry;

  /// Exception `message` field from the body, when present.
  final String? bodyMessage;

  /// How long the server asked us to wait: the `Retry-After` header, or
  /// `retryAfterSeconds` in the body.
  final Duration? retryAfter;

  /// When an exhausted quota period resets (HTTP 402), if the server said.
  final DateTime? resetAt;

  /// The quota meter that is exhausted (`events`, `spans`, `replays`).
  final String? meter;

  /// HTTP 429, or the typed `ApiRateLimitedException` body.
  bool get isRateLimited =>
      statusCode == 429 ||
      (className ?? '').contains('ApiRateLimitedException');

  /// HTTP 402, or the typed `ApiQuotaExceededException` body. Not retried:
  /// the batch is dropped and the meter paused until [resetAt].
  bool get isQuotaExceeded =>
      statusCode == 402 ||
      (className ?? '').contains('ApiQuotaExceededException');

  /// Worth trying again later: network errors and timeouts (no status),
  /// 408, 5xx, rate limits, or a body that says `retry: true`. A body that
  /// says `retry: false` is never transient.
  bool get isTransient {
    if (isQuotaExceeded || retry == false) return false;
    if (isRateLimited || retry == true) return true;
    final status = statusCode;
    return status == null || status == 408 || status >= 500;
  }

  @override
  String toString() => 'TransportException: $message';
}
