import '../analytics/analytics_event.dart';
import '../event.dart';
import '../tracing/span.dart';
import 'transport.dart';

/// Test double that records event, span, and analytics batches.
class FakeTransport implements Transport {
  final List<List<Event>> batches = [];
  final List<List<FinishedSpan>> spanBatches = [];
  final List<List<AnalyticsEvent>> analyticsBatches = [];

  @override
  Future<void> sendBatch(List<Event> events) async {
    batches.add(List.unmodifiable(events));
  }

  @override
  Future<void> sendSpanBatch(List<FinishedSpan> spans) async {
    spanBatches.add(List.unmodifiable(spans));
  }

  @override
  Future<void> sendAnalyticsBatch(List<AnalyticsEvent> events) async {
    analyticsBatches.add(List.unmodifiable(events));
  }
}
