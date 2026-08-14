import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:talaria/src/transport/fake_transport.dart';
import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    await Talaria.reset();
    RuntimeContext.clearCurrent();
  });

  TalariaOptions options({
    bool enableTracing = false,
    double? tracesSampleRate,
  }) {
    return TalariaOptions(
      dsn: 'https://api.example.com',
      apiKey: 'tal_live_test_key_for_unit_tests',
      environment: 'development',
      enableTracing: enableTracing,
      tracesSampleRate: tracesSampleRate,
      defaultIntegrations: false,
      flushIntervalMs: 0,
    );
  }

  test('errors attach breadcrumbs and trace ids', () async {
    final transport = FakeTransport();
    final client = TalariaClient(
      options(tracesSampleRate: 1.0),
      transport: transport,
    );

    final txn = client.startTransaction('checkout');
    client.addBreadcrumb(Breadcrumb(
      type: 'navigation',
      message: '/checkout',
    ));
    client.addBreadcrumb(Breadcrumb(
      type: 'http',
      message: 'GET /pay',
    ));

    try {
      throw StateError('pay failed');
    } catch (e, st) {
      await client.captureException(e, stackTrace: st);
    }
    await client.flush();

    final event = transport.batches.first.single;
    expect(event.traceId, txn.traceId);
    expect(event.spanId, txn.spanId);
    expect(event.breadcrumbs, isNotNull);
    expect(event.breadcrumbs, hasLength(2));
    expect(event.breadcrumbs!.first['__className__'], 'BreadcrumbDto');

    txn.finish();
    await client.flush();
    expect(transport.spanBatches, isNotEmpty);
    await client.close();
  });

  test('processor can populate url and requestId', () async {
    RuntimeContext.setCurrent(url: 'https://app.example/old', requestId: 'r1');
    final transport = FakeTransport();
    final client = TalariaClient(options(), transport: transport);
    client.addProcessor((bag) {
      return {
        ...bag,
        'url': 'https://app.example/from-processor',
        'requestId': 'req-from-processor',
      };
    });

    await client.warning('hi');
    await client.flush();

    final event = transport.batches.first.single;
    expect(event.url, 'https://app.example/from-processor');
    expect(event.requestId, 'req-from-processor');
    await client.close();
  });

  test('RuntimeContext collect uses setCurrent', () {
    RuntimeContext.clearCurrent();
    expect(RuntimeContext.collect()['url'], isNull);
    RuntimeContext.setCurrent(url: '/home', requestId: 'abc');
    final bag = RuntimeContext.collect();
    expect(bag['url'], '/home');
    expect(bag['requestId'], 'abc');
  });

  test('HttpTransport posts IngestSpanBatchInput envelope', () async {
    Map<String, dynamic>? body;
    String? path;
    final httpClient = MockClient((request) async {
      path = request.url.path;
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('{}', 200);
    });

    final transport = HttpTransport(
      baseUrl: 'https://api.example.com',
      apiKey: 'tal_live_testkey',
      httpClient: httpClient,
    );

    await transport.sendSpanBatch([
      FinishedSpan(
        traceId: '0af7651916cd43dd8448eb211c80319c',
        spanId: 'b7ad6b7169203331',
        name: 'GET /x',
        kind: SpanKind.client,
        startTime: DateTime.utc(2026, 1, 1, 0, 0, 0),
        endTime: DateTime.utc(2026, 1, 1, 0, 0, 1),
        environment: Environment.production,
        attributes: {'http.request.method': 'GET'},
      ),
    ]);

    expect(path, '/spans/ingestBatch');
    expect(body!['input']['__className__'], 'IngestSpanBatchInput');
    final spans = body!['input']['spans'] as List;
    expect(spans.single['__className__'], 'IngestSpanInput');
    expect(spans.single['traceId'], '0af7651916cd43dd8448eb211c80319c');
    expect(spans.single['kind'], 'client');
  });

  test('TalariaHttpClient injects traceparent and skips ingest URLs', () async {
    final transport = FakeTransport();
    final client = TalariaClient(
      options(tracesSampleRate: 1.0),
      transport: transport,
    );
    client.startTransaction('screen');

    final seen = <String, String>{};
    Uri? lastUri;
    final inner = MockClient((request) async {
      lastUri = request.url;
      seen.addAll(request.headers);
      return http.Response('ok', 200);
    });

    final wrapped = TalariaHttpClient(inner, client: client);
    await wrapped.get(Uri.parse('https://api.partner.dev/v1/pay?token=secret'));

    expect(seen[Traceparent.headerName], isNotNull);
    expect(seen[Traceparent.headerName], startsWith('00-'));
    expect(lastUri.toString(), contains('token=secret'));

    await wrapped.post(
      Uri.parse('https://api.example.com/spans/ingestBatch'),
      body: '{}',
    );
    // Ingest path is not given a new traceparent from a nested span; the
    // request still goes through. Span count should be the HTTP client call only.
    await client.flush();
    final httpSpans = transport.spanBatches
        .expand((b) => b)
        .where((s) => s.kind == SpanKind.client)
        .toList();
    expect(httpSpans, hasLength(1));
    expect(httpSpans.single.attributes['url.path'], '/v1/pay');
    expect(httpSpans.single.attributes['http.response.status_code'], '200');

    await client.close();
  });

  test('TalariaHttpClient marks 5xx as error spans', () async {
    final transport = FakeTransport();
    final client = TalariaClient(
      options(tracesSampleRate: 1.0),
      transport: transport,
    );

    final inner = MockClient((request) async => http.Response('nope', 503));
    final wrapped = TalariaHttpClient(inner, client: client);
    await wrapped.get(Uri.parse('https://api.partner.dev/fail'));
    await client.flush();

    final span = transport.spanBatches.expand((b) => b).single;
    expect(span.status, SpanStatus.error);
    expect(span.isRoot, isTrue);
    await client.close();
  });

  test('getTraceparent matches the active span', () async {
    final transport = FakeTransport();
    final client = TalariaClient(
      options(tracesSampleRate: 1.0),
      transport: transport,
    );

    expect(client.getTraceparent(), isNull);
    final txn = client.startTransaction('checkout');
    final header = client.getTraceparent();
    expect(header, isNotNull);
    expect(header, startsWith('00-${txn.traceId}-${txn.spanId}-'));
    txn.finish();
    await client.close();
  });
}
