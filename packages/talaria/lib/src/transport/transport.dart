import '../analytics/analytics_event.dart';
import '../event.dart';
import '../tracing/span.dart';

/// Sends a batch of events to Talaria ingest.
abstract class Transport {
  Future<void> sendBatch(List<Event> events);

  /// Span ingest. Default is a no-op so event-only fakes keep compiling.
  Future<void> sendSpanBatch(List<FinishedSpan> spans) async {}

  /// Analytics ingest. Default is a no-op so event-only fakes keep compiling.
  Future<void> sendAnalyticsBatch(List<AnalyticsEvent> events) async {}
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

  @override
  String toString() => 'TransportException: $message';
}
