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

  /// Optional evaluate handler for unit tests.
  Future<Map<String, Object?>> Function(Map<String, Object?> input)?
      onEvaluateFlags;

  /// Optional definitions download handler for unit tests.
  Future<Map<String, Object?>> Function(Map<String, Object?> input)?
      onDownloadFlagDefinitions;

  final List<Map<String, Object?>> evaluateCalls = [];
  final List<Map<String, Object?>> downloadDefinitionCalls = [];

  @override
  Future<Map<String, Object?>> evaluateFlags(
    Map<String, Object?> input,
  ) async {
    evaluateCalls.add(Map<String, Object?>.from(input));
    final handler = onEvaluateFlags;
    if (handler != null) {
      return handler(input);
    }
    return const {};
  }

  @override
  Future<Map<String, Object?>> downloadFlagDefinitions(
    Map<String, Object?> input,
  ) async {
    downloadDefinitionCalls.add(Map<String, Object?>.from(input));
    final handler = onDownloadFlagDefinitions;
    if (handler != null) {
      return handler(input);
    }
    return const {};
  }
}
