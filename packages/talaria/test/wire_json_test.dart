import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:talaria/src/protocol/exception_payload_builder.dart';
import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

/// Regression: TIS route schemas are plain JSON.
///
/// Live `ingest-nz1` accepts these bodies (401 `invalid_key` once the
/// schema matches, 400 `invalid_body` when the batch key or a field is
/// wrong). `POST /v1/analytics` reads `events`. `POST /v1/screen-heatmaps`
/// reads `screenViews`.
void main() {
  const apiKey =
      'tal_sk_test_nz1_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg3B299S';

  test('POST /v1/analytics body is exact plain JSON', () async {
    final body = await _post(
      apiKey: apiKey,
      send: (transport) => transport.sendAnalyticsBatch([
        AnalyticsEvent(
          eventId: 'evt-1',
          name: 'product_viewed',
          kind: AnalyticsEventKind.track,
          anonymousId: 'anon-1',
          sessionId: 'sess-1',
          timestamp: DateTime.utc(2026, 1, 1),
          propertiesJson: '{"price":9.5}',
        ),
      ]),
    );

    expect(body.path, '/v1/analytics');
    expect(
      body.json,
      '{"events":[{"eventId":"evt-1","name":"product_viewed","kind":"track","anonymousId":"anon-1","sessionId":"sess-1","timestamp":"2026-01-01T00:00:00.000Z","propertiesJson":"{\\"price\\":9.5}"}]}',
    );
    expect(body.json.contains('__className__'), isFalse);
    expect(body.json.contains('IngestAnalytics'), isFalse);
  });

  test('POST /v1/events log body is exact plain JSON', () async {
    final body = await _post(
      apiKey: apiKey,
      send: (transport) => transport.sendBatch([
        Event(
          message: 'checkout started',
          level: SeverityLevel.info,
          platform: 'dart',
          timestamp: '2026-01-01T00:00:00.000Z',
          breadcrumbs: [
            {
              'timestamp': '2026-01-01T00:00:00.000Z',
              'type': 'navigation',
              'message': '/checkout',
            },
          ],
        ),
      ]),
    );

    expect(body.path, '/v1/events');
    expect(
      body.json,
      '{"events":[{"message":"checkout started","level":"info","eventType":"info","platform":"dart","timestamp":"2026-01-01T00:00:00.000Z","breadcrumbs":[{"timestamp":"2026-01-01T00:00:00.000Z","type":"navigation","message":"/checkout"}]}]}',
    );
    expect(body.json.contains('__className__'), isFalse);
    expect(body.json.contains('IngestEvent'), isFalse);
    expect(body.json.contains('BreadcrumbDto'), isFalse);
  });

  test('POST /v1/events exception body is exact plain JSON', () async {
    final body = await _post(
      apiKey: apiKey,
      send: (transport) => transport.sendBatch([
        Event(
          message: 'bad input',
          level: SeverityLevel.error,
          platform: 'flutter',
          timestamp: '2026-01-01T00:00:00.000Z',
          exception: {
            'values': [
              {
                'type': 'FormatException',
                'value': 'bad',
                'mechanism': {
                  'type': 'generic',
                  'handled': true,
                  'synthetic': false,
                },
                'stacktrace': {
                  'frames': [
                    {
                      'platform': 'flutter',
                      'inApp': true,
                      'functionName': 'checkout',
                      'lineno': 12,
                    },
                  ],
                },
              },
            ],
          },
        ),
      ]),
    );

    expect(body.path, '/v1/events');
    expect(
      body.json,
      '{"events":[{"message":"bad input","level":"error","eventType":"error","exception":{"values":[{"type":"FormatException","value":"bad","mechanism":{"type":"generic","handled":true,"synthetic":false},"stacktrace":{"frames":[{"platform":"flutter","inApp":true,"functionName":"checkout","lineno":12}]}}]},"platform":"flutter","timestamp":"2026-01-01T00:00:00.000Z"}]}',
    );
    expect(body.json.contains('__className__'), isFalse);
    expect(body.json.contains('ExceptionDataDto'), isFalse);
    expect(body.json.contains('StackFrameDto'), isFalse);
  });

  test('POST /v1/spans body is exact plain JSON', () async {
    final body = await _post(
      apiKey: apiKey,
      send: (transport) => transport.sendSpanBatch([
        FinishedSpan(
          traceId: '0af7651916cd43dd8448eb211c80319c',
          spanId: 'b7ad6b7169203331',
          parentSpanId: '00f067aa0ba902b7',
          name: 'GET /x',
          kind: SpanKind.client,
          startTime: DateTime.utc(2026, 1, 1),
          endTime: DateTime.utc(2026, 1, 1, 0, 0, 1),
          status: SpanStatus.ok,
          attributes: {'http.request.method': 'GET'},
          events: [
            SpanEvent(
              name: 'retry',
              timestamp: DateTime.utc(2026, 1, 1, 0, 0, 0, 500),
            ),
          ],
          links: [
            const SpanLink(
              traceId: '4bf92f3577b34da6a3ce929d0e0e4736',
              spanId: '00f067aa0ba902b7',
            ),
          ],
        ),
      ]),
    );

    expect(body.path, '/v1/spans');
    expect(
      body.json,
      '{"spans":[{"traceId":"0af7651916cd43dd8448eb211c80319c","spanId":"b7ad6b7169203331","name":"GET /x","kind":"client","startTime":"2026-01-01T00:00:00.000Z","endTime":"2026-01-01T00:00:01.000Z","parentSpanId":"00f067aa0ba902b7","status":"ok","attributes":{"http.request.method":"GET"},"events":[{"timestamp":"2026-01-01T00:00:00.500Z","name":"retry"}],"links":[{"traceId":"4bf92f3577b34da6a3ce929d0e0e4736","spanId":"00f067aa0ba902b7"}]}]}',
    );
    expect(body.json.contains('__className__'), isFalse);
    expect(body.json.contains('IngestSpan'), isFalse);
    expect(body.json.contains('SpanEventDto'), isFalse);
    expect(body.json.contains('SpanLinkDto'), isFalse);
  });

  test('POST /v1/screen-heatmaps body uses screenViews', () async {
    final body = await _post(
      apiKey: apiKey,
      send: (transport) async {
        await transport.sendScreenHeatmapBatch([
          {
            'screenViewId': '11111111-1111-4111-8111-111111111111',
            'screenKey': 'Home',
            'anonymousId': 'anon-1',
            'sessionId': 'sess-1',
            'userId': null,
            'replayId': null,
            'startedAt': '2026-01-01T00:00:00.000Z',
            'updatedAt': '2026-01-01T00:00:01.000Z',
            'viewportWidth': 390,
            'viewportHeight': 844,
            'contentWidth': 390,
            'contentHeight': 2000,
            'maxDepthPx': 400,
            'initialFoldPx': 844,
            'scrollAxis': 'vertical',
            'deviceClass': 'mobile',
            'orientation': 'portrait',
            'keyboard': false,
            'osName': null,
            'release': null,
            'platform': 'flutter',
            'taps': [
              {
                'tapIndex': 0,
                'occurredAt': '2026-01-01T00:00:00.000Z',
                'path': 'Home/Button',
                'role': 'button',
                'relX': 50,
                'relY': 20,
                'xBp': 50,
                'yBp': 20,
                'contentX': 100,
                'contentY': 200,
                'rage': false,
                'dead': false,
                'error': false,
                'recordingId': null,
              },
            ],
          },
        ]);
      },
    );

    expect(body.path, '/v1/screen-heatmaps');
    expect(body.json.contains('screenHeatmaps'), isFalse);
    expect(body.json.contains('__className__'), isFalse);
    final decoded = jsonDecode(body.json) as Map<String, Object?>;
    expect(decoded.keys, ['screenViews']);
    final view = (decoded['screenViews']! as List).single as Map;
    expect(view['keyboard'], isFalse);
    final tap = (view['taps']! as List).single as Map;
    expect(tap['relX'], 50);
    expect(tap['relX'], isA<int>());
    expect(tap['recordingId'], isNull);
  });

  test('POST /v1/screen-heatmaps/snapshots encodes png bytes as base64',
      () async {
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    final bytes = base64Decode(png);
    final body = await _post(
      apiKey: apiKey,
      send: (transport) async {
        await transport.uploadScreenHeatmapSnapshot({
          'screenViewId': '11111111-1111-4111-8111-111111111111',
          'pngBytes': bytes,
          'manifestJson': '{}',
          'viewportWidth': 390,
          'viewportHeight': 844,
          'contentHeight': 2000,
          'capturedAt': '2026-01-01T00:00:00.000Z',
          'tiles': [
            {'offsetPx': 0, 'pngBytes': bytes},
          ],
        });
      },
    );

    expect(body.path, '/v1/screen-heatmaps/snapshots');
    expect(
      body.json,
      '{"screenViewId":"11111111-1111-4111-8111-111111111111","pngBytes":"$png","manifestJson":"{}","viewportWidth":390,"viewportHeight":844,"contentHeight":2000,"capturedAt":"2026-01-01T00:00:00.000Z","tiles":[{"offsetPx":0,"pngBytes":"$png"}]}',
    );
  });

  test('POST /v1/screen-heatmaps/recordings encodes frame pngs', () async {
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    final body = await _post(
      apiKey: apiKey,
      send: (transport) async {
        await transport.uploadScreenHeatmapRecording({
          'recordingId': '11111111-1111-4111-8111-111111111111',
          'screenViewId': '22222222-2222-4222-8222-222222222222',
          'frames': [
            {'offsetMs': 0, 'pngBytes': base64Decode(png)},
          ],
        });
      },
    );

    expect(body.path, '/v1/screen-heatmaps/recordings');
    expect(
      body.json,
      '{"recordingId":"11111111-1111-4111-8111-111111111111","screenViewId":"22222222-2222-4222-8222-222222222222","frames":[{"offsetMs":0,"pngBytes":"$png"}]}',
    );
  });

  test('POST /v1/client-reports body is discards', () async {
    final body = await _post(
      apiKey: apiKey,
      send: (transport) async {
        await transport.reportDiscards(const [
          DiscardRow(signal: 'events', reason: 'sample_rate', count: 1),
        ]);
      },
    );

    expect(body.path, '/v1/client-reports');
    expect(
      body.json,
      '{"discards":[{"signal":"events","reason":"sample_rate","count":1}]}',
    );
    expect(body.json.contains('reports'), isFalse);
    expect(body.json.contains('discardedEvents'), isFalse);
  });

  test('built exception trees carry no Serverpod class names', () {
    final payload = ExceptionPayloadBuilder.fromError(
      StateError('nope'),
      StackTrace.current,
    );
    final encoded = jsonEncode(payload);
    expect(encoded.contains('__className__'), isFalse);
    expect(encoded.contains('Dto'), isFalse);
  });
}

class _Captured {
  _Captured(this.path, this.json);

  final String path;
  final String json;
}

Future<_Captured> _post({
  required String apiKey,
  required Future<void> Function(HttpTransport transport) send,
}) async {
  late String path;
  late String json;
  final client = MockClient((request) async {
    path = request.url.path;
    json = request.body;
    return http.Response('{}', 200);
  });
  final transport = HttpTransport(
    url: 'https://ingest-nz1.newtalaria.com',
    apiKey: apiKey,
    httpClient: client,
  );
  await send(transport);
  transport.close();
  return _Captured(path, json);
}
