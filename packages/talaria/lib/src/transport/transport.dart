import '../event.dart';

/// Sends a batch of events to Talaria ingest.
abstract class Transport {
  Future<void> sendBatch(List<Event> events);
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
