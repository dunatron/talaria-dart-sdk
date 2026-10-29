import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

/// `TalariaHttpClient` never instruments Talaria SDK calls, even when an app
/// wraps the ingest client by mistake.
void main() {
  const sdkCalls = [
    'events/ingest',
    'events/ingestBatch',
    'spans/ingestBatch',
    'analytics/ingestBatch',
    'heatmaps/ingestBatch',
    'heatmaps/uploadSnapshot',
    'screenHeatmaps/ingestBatch',
    'screenHeatmaps/uploadSnapshot',
    'screenHeatmaps/uploadRecording',
    'replays/ingestSegment',
    'replays/ingestSegmentBatch',
    'sdk/getConfig',
    'sdk/reportDiscards',
    'flags/evaluate',
    'flags/downloadDefinitions',
    // New /v1/ paths
    'v1/events',
    'v1/spans',
    'v1/analytics',
  ];

  test('every SDK call is an ingest URL, also behind a path prefix', () {
    for (final call in sdkCalls) {
      for (final base in [
        'https://api.example.com',
        'https://example.com/talaria',
      ]) {
        expect(
          TalariaHttpClient.isTalariaIngestUrl(Uri.parse('$base/$call')),
          isTrue,
          reason: '$base/$call',
        );
      }
    }
  });

  test('other calls, including dashboard methods, are not', () {
    for (final call in [
      'flags/list',
      'screenHeatmaps/getRecording',
      'replays/get',
      'projects/list',
      'events',
      'ingestBatch',
      'api/eventsingestBatch',
    ]) {
      expect(
        TalariaHttpClient.isTalariaIngestUrl(
          Uri.parse('https://api.example.com/$call'),
        ),
        isFalse,
        reason: call,
      );
    }
  });
}
