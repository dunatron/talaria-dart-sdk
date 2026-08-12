import '../event.dart';
import 'transport.dart';

/// Test double that records batches.
class FakeTransport implements Transport {
  final List<List<Event>> batches = [];

  @override
  Future<void> sendBatch(List<Event> events) async {
    batches.add(List.unmodifiable(events));
  }
}
