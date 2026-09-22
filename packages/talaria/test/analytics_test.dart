import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:talaria/src/transport/fake_transport.dart';
import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    RuntimeContext.clearCurrent();
    await Talaria.reset();
  });

  TalariaOptions options({
    bool enableAnalytics = false,
    String platform = 'dart',
    TalariaStorage? storage,
  }) {
    return TalariaOptions(
      dsn: 'https://api.example.com',
      apiKey: 'tal_live_test_key_for_unit_tests',
      environment: 'development',
      enableAnalytics: enableAnalytics,
      platform: platform,
      storage: storage,
      defaultIntegrations: false,
      flushIntervalMs: 0,
    );
  }

  test('analytics is off until enableAnalytics or optIn', () async {
    final transport = FakeTransport();
    final client = TalariaClient(options(), transport: transport);

    await client.analytics.track('product_viewed', userId: 'u1');
    await client.flush();
    expect(transport.analyticsBatches, isEmpty);

    client.analytics.optIn();
    await client.analytics.track('product_viewed', userId: 'u1');
    await client.flush();
    expect(transport.analyticsBatches, hasLength(1));
    expect(transport.analyticsBatches.single.single.name, 'product_viewed');
    await client.close();
  });

  test('identify sets user and emits \$identify', () async {
    final transport = FakeTransport();
    final client = TalariaClient(
      options(enableAnalytics: true, platform: 'flutter'),
      transport: transport,
    );

    await client.analytics.identify('user_123', traits: {'plan': 'team'});
    await client.flush();

    final event = transport.analyticsBatches.single.single;
    expect(event.kind, AnalyticsEventKind.identify);
    expect(event.name, r'$identify');
    expect(event.userId, 'user_123');
    expect(event.anonymousId, client.anonymousId);
    expect(event.sessionId, client.sessionId);
    expect(event.propertiesJson, contains('team'));

    await client.captureMessage('after identify');
    await client.flush();
    expect(transport.batches.single.single.userId, 'user_123');
    await client.close();
  });

  test('track page and screen use default names', () async {
    final transport = FakeTransport();
    final client = TalariaClient(
      options(enableAnalytics: true, platform: 'flutter'),
      transport: transport,
    );

    await client.analytics.track(
      'product_viewed',
      properties: {'product_id': '123', 'price': 129.99},
    );
    await client.analytics.page();
    await client.analytics.screen();
    await client.flush();

    final events = transport.analyticsBatches.expand((b) => b).toList();
    expect(events.map((e) => e.name), [
      'product_viewed',
      r'$pageview',
      r'$screen',
    ]);
    expect(events[0].kind, AnalyticsEventKind.track);
    expect(events[1].kind, AnalyticsEventKind.page);
    expect(events[2].kind, AnalyticsEventKind.screen);
    expect(jsonDecode(events[0].propertiesJson!),
        {'product_id': '123', 'price': 129.99});
    await client.close();
  });

  test('stamps timezone and omits empty context fields on the wire', () async {
    RuntimeContext.setTimezone('Pacific/Auckland');
    final transport = FakeTransport();
    final client = TalariaClient(
      options(enableAnalytics: true, platform: 'flutter'),
      transport: transport,
    );

    await client.analytics.track('product_viewed', userId: 'u1');
    await client.flush();

    final event = transport.analyticsBatches.single.single;
    expect(event.timezone, 'Pacific/Auckland');
    final wire = event.toWire();
    expect(wire['timezone'], 'Pacific/Auckland');
    expect(wire.containsKey('userAgent'), isFalse);
    expect(wire.containsKey('browserName'), isFalse);
    await client.close();
  });

  test('server dart drops analytics without caller identity', () async {
    final transport = FakeTransport();
    final client = TalariaClient(
      options(enableAnalytics: true),
      transport: transport,
    );

    await client.analytics.track('orphan');
    await client.flush();
    expect(transport.analyticsBatches, isEmpty);

    await client.analytics.track('ok', userId: 'user_1');
    await client.flush();
    expect(transport.analyticsBatches, hasLength(1));
    expect(transport.analyticsBatches.single.single.userId, 'user_1');
    expect(transport.analyticsBatches.single.single.anonymousId, isNotEmpty);
    await client.close();
  });

  test('server dart accepts zone anonymousId', () async {
    final transport = FakeTransport();
    final client = TalariaClient(
      options(enableAnalytics: true),
      transport: transport,
    );

    await RuntimeContext.runWithAsync(() async {
      await client.analytics.track('zoned');
    }, anonymousId: 'anon-zone');
    await client.flush();

    expect(transport.analyticsBatches.single.single.anonymousId, 'anon-zone');
    await client.close();
  });

  test('reset rotates identity and clears user', () async {
    final storage = MemoryTalariaStorage();
    final transport = FakeTransport();
    final client = TalariaClient(
      options(enableAnalytics: true, platform: 'flutter', storage: storage),
      transport: transport,
    );

    await client.analytics.identify('user_123');
    await client.flush();
    final anon = client.anonymousId;
    final session = client.sessionId;
    await client.analytics.reset();

    expect(client.anonymousId, isNot(anon));
    expect(client.sessionId, isNot(session));
    expect(storage.read(Identity.anonymousIdKey), client.anonymousId);

    await client.analytics.track('after_reset');
    await client.flush();
    final last = transport.analyticsBatches.expand((b) => b).last;
    expect(last.name, 'after_reset');
    expect(last.userId, isNull);
    expect(last.anonymousId, client.anonymousId);
    await client.close();
  });

  test('stamps live traceId and spanId', () async {
    final transport = FakeTransport();
    final client = TalariaClient(
      TalariaOptions(
        dsn: 'https://api.example.com',
        apiKey: 'tal_live_test_key_for_unit_tests',
        environment: 'development',
        enableAnalytics: true,
        platform: 'flutter',
        tracesSampleRate: 1.0,
        defaultIntegrations: false,
        flushIntervalMs: 0,
      ),
      transport: transport,
    );

    final txn = client.startTransaction('checkout');
    await client.analytics.track('pay');
    await client.flush();

    final event = transport.analyticsBatches.single.single;
    expect(event.traceId, txn.traceId);
    expect(event.spanId, txn.spanId);
    txn.finish();
    await client.close();
  });

  test('events and spans include anonymousId', () async {
    final transport = FakeTransport();
    final client = TalariaClient(
      TalariaOptions(
        dsn: 'https://api.example.com',
        apiKey: 'tal_live_test_key_for_unit_tests',
        environment: 'development',
        tracesSampleRate: 1.0,
        defaultIntegrations: false,
        flushIntervalMs: 0,
      ),
      transport: transport,
    );

    await client.warning('hello');
    final span = client.startTransaction('work');
    span.finish();
    await client.flush();

    expect(transport.batches.single.single.anonymousId, client.anonymousId);
    expect(transport.batches.single.single.sessionId, client.sessionId);
    expect(transport.spanBatches.single.single.anonymousId, client.anonymousId);
    await client.close();
  });

  test('HttpTransport posts IngestAnalyticsEventBatchInput envelope', () async {
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

    await transport.sendAnalyticsBatch([
      AnalyticsEvent(
        eventId: 'evt-1',
        name: 'product_viewed',
        kind: AnalyticsEventKind.track,
        anonymousId: 'anon-1',
        sessionId: 'sess-1',
        timestamp: DateTime.utc(2026, 1, 1, 0, 0, 0),
        propertiesJson: '{"price":9.5}',
      ),
    ]);

    expect(path, '/analytics/ingestBatch');
    expect(body!['input']['__className__'], 'IngestAnalyticsEventBatchInput');
    final events = body!['input']['events'] as List;
    expect(events.single['__className__'], 'IngestAnalyticsEventInput');
    expect(events.single['name'], 'product_viewed');
    expect(events.single['kind'], 'track');
    expect(events.single['anonymousId'], 'anon-1');
    expect(events.single['sessionId'], 'sess-1');
    expect(events.single['propertiesJson'], '{"price":9.5}');
  });

  test('missing analyticsWrite disables analytics only', () async {
    final transport = _ThrowingAnalyticsTransport(
      TransportException(
        'Talaria analytics/ingestBatch failed: HTTP 400',
        statusCode: 400,
        className: 'ApiUnauthorizedException',
        retry: false,
        bodyMessage: 'API key lacks required scope: analyticsWrite',
      ),
    );
    final client = TalariaClient(
      options(enableAnalytics: true, platform: 'flutter'),
      transport: transport,
    );

    await client.analytics.track('one');
    await client.flush();
    await client.analytics.track('two');
    await client.flush();
    await client.warning('still events');
    await client.flush();

    expect(transport.analyticsSendCount, 1);
    expect(client.isAnalyticsIngestDisabled, isTrue);
    expect(client.isEventsIngestDisabled, isFalse);
    expect(transport.eventSendCount, 1);
    await client.close();
  });

  test('permanent ingest error disables analytics too', () async {
    final transport = _ThrowingAnalyticsTransport(
      TransportException(
        'Talaria events/ingestBatch failed: HTTP 400',
        statusCode: 400,
        className: 'ApiUnauthorizedException',
        retry: false,
        bodyMessage: 'Invalid API key',
      ),
      failEvents: true,
    );
    final client = TalariaClient(
      options(enableAnalytics: true, platform: 'flutter'),
      transport: transport,
    );

    await client.warning('first');
    await client.flush();
    await client.analytics.track('nope');
    await client.flush();

    expect(client.isEventsIngestDisabled, isTrue);
    expect(client.isAnalyticsIngestDisabled, isTrue);
    expect(transport.analyticsSendCount, 0);
    await client.close();
  });

  test('facade analytics API', () async {
    final transport = FakeTransport();
    await Talaria.init(
      options(enableAnalytics: true, platform: 'flutter'),
      transport: transport,
    );

    await Talaria.analytics.track('from_facade');
    await Talaria.flush();
    expect(Talaria.analytics.isEnabled, isTrue);
    expect(transport.analyticsBatches.single.single.name, 'from_facade');
  });
}

class _ThrowingAnalyticsTransport implements Transport {
  _ThrowingAnalyticsTransport(this.error, {this.failEvents = false});

  final TransportException error;
  final bool failEvents;
  int analyticsSendCount = 0;
  int eventSendCount = 0;

  @override
  Future<void> sendBatch(List<Event> events) async {
    eventSendCount++;
    if (failEvents) {
      throw error;
    }
  }

  @override
  Future<void> sendSpanBatch(List<FinishedSpan> spans) async {}

  @override
  Future<void> sendAnalyticsBatch(List<AnalyticsEvent> events) async {
    analyticsSendCount++;
    throw error;
  }
}
