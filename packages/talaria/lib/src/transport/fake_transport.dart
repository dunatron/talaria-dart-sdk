import '../analytics/analytics_event.dart';
import '../event.dart';
import '../tracing/span.dart';
import 'discards.dart';
import 'transport.dart';

/// Test double that records event, span, and analytics batches.
class FakeTransport implements Transport {
  final List<List<Event>> batches = [];
  final List<List<FinishedSpan>> spanBatches = [];
  final List<List<AnalyticsEvent>> analyticsBatches = [];
  final List<List<DiscardRow>> discardReports = [];

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

  @override
  Future<Map<String, Object?>> sendScreenHeatmapBatch(
    List<Map<String, Object?>> screenViews,
  ) async =>
      const {};

  @override
  Future<void> uploadScreenHeatmapSnapshot(Map<String, Object?> input) async {}

  @override
  Future<void> uploadScreenHeatmapRecording(Map<String, Object?> input) async {}

  @override
  Future<void> reportDiscards(List<DiscardRow> discards) async {
    discardReports.add(List.unmodifiable(discards));
  }
}
