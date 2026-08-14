import '../event.dart';
import '../tracing/span.dart';
import 'transport.dart';

/// Test double that records event and span batches.
class FakeTransport implements Transport {
  final List<List<Event>> batches = [];
  final List<List<FinishedSpan>> spanBatches = [];

  @override
  Future<void> sendBatch(List<Event> events) async {
    batches.add(List.unmodifiable(events));
  }

  @override
  Future<void> sendSpanBatch(List<FinishedSpan> spans) async {
    spanBatches.add(List.unmodifiable(spans));
  }
}
