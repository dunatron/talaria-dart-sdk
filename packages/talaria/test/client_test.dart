import 'package:talaria/src/transport/fake_transport.dart';
import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    await Talaria.reset();
  });

  TalariaOptions options({
    SeverityLevel minLevel = SeverityLevel.debug,
    bool enforce = false,
    Map<String, LoggerPreset>? loggers,
    BeforeSendCallback? beforeSend,
    double sampleRate = 1.0,
  }) {
    return TalariaOptions(
      url: 'https://api.example.com',
      apiKey:
          'tal_sk_test_nz1_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg3B299S',
      minLevel: minLevel,
      enforceDefaultLevel: enforce,
      loggers: loggers,
      beforeSend: beforeSend,
      sampleRate: sampleRate,
      defaultIntegrations: false,
      flushIntervalMs: 0,
      maxBatchSize: 50,
    );
  }

  test('direct client respects minLevel', () async {
    final transport = FakeTransport();
    final client = TalariaClient(
      options(minLevel: SeverityLevel.warning),
      transport: transport,
    );

    await client.info('nope');
    await client.warning('yep');
    await client.flush();

    expect(transport.batches, hasLength(1));
    expect(transport.batches.first.single.message, 'yep');
    await client.close();
  });

  test('scoped logger may go below root when enforce is false', () async {
    final transport = FakeTransport();
    final client = TalariaClient(
      options(minLevel: SeverityLevel.warning),
      transport: transport,
    );

    final scoped = client.logger(minLevel: SeverityLevel.info);
    await scoped.info('verbose');
    await client.flush();

    expect(transport.batches, hasLength(1));
    expect(transport.batches.first.single.message, 'verbose');
    await client.close();
  });

  test('enforceDefaultLevel clamps scoped loggers', () async {
    final transport = FakeTransport();
    final client = TalariaClient(
      options(minLevel: SeverityLevel.warning, enforce: true),
      transport: transport,
    );

    final scoped = client.logger(minLevel: SeverityLevel.info);
    await scoped.info('blocked');
    await client.flush();

    expect(transport.batches, isEmpty);
    await client.close();
  });

  test('named logger presets merge tags', () async {
    final transport = FakeTransport();
    final client = TalariaClient(
      options(
        loggers: {
          'checkout': LoggerPreset(
            tags: {'area': 'checkout'},
            minLevel: SeverityLevel.info,
          ),
        },
      ),
      transport: transport,
    );

    await client.logger(name: 'checkout', tags: {'request': '1'}).info('hi');
    await client.flush();

    final tags = transport.batches.first.single.tags!;
    expect(tags['area'], 'checkout');
    expect(tags['request'], '1');
    await client.close();
  });

  test('beforeSend can drop events', () async {
    final transport = FakeTransport();
    final client = TalariaClient(
      options(beforeSend: (event, hint) => null),
      transport: transport,
    );

    await client.error('drop me');
    await client.flush();
    expect(transport.batches, isEmpty);
    await client.close();
  });

  test('captureException builds structured exception', () async {
    final transport = FakeTransport();
    final client = TalariaClient(options(), transport: transport);

    try {
      throw FormatException('bad');
    } catch (e, st) {
      await client.captureException(e, stackTrace: st);
    }
    await client.flush();

    final event = transport.batches.first.single;
    expect(event.level, SeverityLevel.error);
    expect(event.platform, 'dart');
    expect(event.exception?.containsKey('__className__'), isFalse);
    expect(event.exception?['values'], isA<List<Object?>>());
    expect(event.stackTrace, isNotNull);
    await client.close();
  });

  test('facade init and capture', () async {
    final transport = FakeTransport();
    await Talaria.init(options(), transport: transport);
    await Talaria.warning('from facade');
    await Talaria.flush();
    expect(transport.batches.first.single.message, 'from facade');
  });

  test(
    'apiKey must be a tal_pk_ or tal_sk_ key with a valid checksum',
    () {
      expect(
        () => TalariaOptions(url: 'https://api.example.com', apiKey: 'wrong'),
        throwsArgumentError,
      );
      expect(
        () => TalariaOptions(
          url: 'https://api.example.com',
          apiKey:
              'tal_live_test_nz1_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg3B299S',
        ),
        throwsArgumentError,
      );
    },
  );

  test('invalid key disables further event capture', () async {
    final transport = _ThrowingTransport(
      TransportException(
        'Talaria /v1/events failed: HTTP 400',
        statusCode: 400,
        className: 'ApiUnauthorizedException',
        retry: false,
        bodyMessage: 'Invalid API key',
      ),
    );
    final client = TalariaClient(options(), transport: transport);

    await client.captureMessage('first');
    await client.flush();
    await client.captureMessage('second');
    await client.flush();

    expect(transport.sendCount, 1);
    expect(client.isEventsIngestDisabled, isTrue);
    expect(client.isSpansIngestDisabled, isTrue);
    await client.close();
  });

  test('quota (HTTP 402) pauses events but does not disable ingest', () async {
    final transport = _ThrowingTransport(
      TransportException(
        'Talaria /v1/events failed: HTTP 402',
        statusCode: 402,
        className: 'ApiQuotaExceededException',
        bodyMessage: 'quota exceeded',
        meter: 'events',
      ),
    );
    var now = DateTime.utc(2026, 10, 19);
    final client = TalariaClient(
      options(),
      transport: transport,
      clock: () => now,
    );

    await client.captureMessage('first');
    await client.flush();
    await client.captureMessage('second');
    await client.flush();
    expect(transport.sendCount, 1, reason: 'paused until the reset');

    now = now.add(const Duration(minutes: 11));
    await client.captureMessage('third');
    await client.flush();
    expect(transport.sendCount, 2);
    expect(client.isEventsIngestDisabled, isFalse);
    await client.close();
  });

  test('5xx backs off but does not disable ingest', () async {
    final transport = _ThrowingTransport(
      TransportException(
        'Talaria /v1/events failed: HTTP 503',
        statusCode: 503,
      ),
    );
    var now = DateTime.utc(2026, 10, 19);
    final client = TalariaClient(
      options(),
      transport: transport,
      clock: () => now,
    );

    await client.captureMessage('first');
    await client.flush();
    await client.captureMessage('second');
    await client.flush();
    expect(transport.sendCount, 1, reason: 'backing off');

    now = now.add(const Duration(seconds: 2));
    await client.flush();
    expect(transport.sendCount, 2);
    expect(client.isEventsIngestDisabled, isFalse);
    await client.close();
  });
}

class _ThrowingTransport implements Transport {
  _ThrowingTransport(this.error);

  final TransportException error;
  int sendCount = 0;

  @override
  Future<void> sendBatch(List<Event> events) async {
    sendCount++;
    throw error;
  }

  @override
  Future<void> sendSpanBatch(List<FinishedSpan> spans) async {
    throw error;
  }

  @override
  Future<void> sendAnalyticsBatch(List<AnalyticsEvent> events) async {
    throw error;
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
  Future<void> reportDiscards(List<DiscardRow> discards) async {}

  @override
  Future<Map<String, Object?>> evaluateFlags(
    Map<String, Object?> input,
  ) async =>
      const {};

  @override
  Future<Map<String, Object?>> downloadFlagDefinitions(
    Map<String, Object?> input,
  ) async =>
      const {};
}
