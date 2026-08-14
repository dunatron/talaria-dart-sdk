import '../event.dart';
import '../tracing/span.dart';

/// Sends a batch of events to Talaria ingest.
abstract class Transport {
  Future<void> sendBatch(List<Event> events);

  /// Span ingest. Default is a no-op so event-only fakes keep compiling.
  Future<void> sendSpanBatch(List<FinishedSpan> spans) async {}
}

/// Raised when ingest HTTP fails.
class TransportException implements Exception {
  TransportException(this.message, {this.statusCode, this.cause});

  final String message;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() => 'TransportException: $message';
}
