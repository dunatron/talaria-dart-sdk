import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:talaria/src/protocol/exception_payload_builder.dart';
import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

/// Regression: TIS route schemas are plain JSON. A Serverpod `__className__`
/// (or any other wire class marker) makes ingest answer 400
/// "body does not match the route schema".
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
      '{"analytics":[{"eventId":"evt-1","name":"product_viewed","kind":"track","anonymousId":"anon-1","sessionId":"sess-1","timestamp":"2026-01-01T00:00:00.000Z","propertiesJson":"{\\"price\\":9.5}"}]}',
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
