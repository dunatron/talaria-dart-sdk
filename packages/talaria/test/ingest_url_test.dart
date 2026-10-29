import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

/// `TalariaHttpClient` never instruments Talaria SDK calls, even when an app
/// wraps the ingest client by mistake.
void main() {
  // Only /v1/ paths (hard cut - no old paths)
  const sdkCalls = [
    'v1/events',
    'v1/spans',
    'v1/analytics',
    'v1/replays',
    'v1/heatmaps',
    'v1/screen-heatmaps',
    'v1/sdk',
    'v1/flags',
    'v1/monitors',
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

  test('other calls, including dashboard methods and old paths, are not', () {
    for (final call in [
      'flags/list',
      'screen-heatmaps/getRecording',
      'replays/get',
      'projects/list',
      'events',
      'ingestBatch',
      'api/eventsingestBatch',
      // Old paths are NOT ingest URLs (hard cut)
      'events/ingest',
      'events/ingestBatch',
      'spans/ingestBatch',
      'analytics/ingestBatch',
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
