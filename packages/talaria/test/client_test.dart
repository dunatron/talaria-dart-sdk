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
      dsn: 'https://api.example.com',
      apiKey: 'tal_live_test_key_for_unit_tests',
      environment: 'development',
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
    final client = TalariaClient(options(minLevel: SeverityLevel.warning),
        transport: transport);

    await client.info('nope');
    await client.warning('yep');
    await client.flush();

    expect(transport.batches, hasLength(1));
    expect(transport.batches.first.single.message, 'yep');
    await client.close();
  });

  test('scoped logger may go below root when enforce is false', () async {
    final transport = FakeTransport();
    final client = TalariaClient(options(minLevel: SeverityLevel.warning),
        transport: transport);

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
    expect(event.exception?['__className__'], 'ExceptionDataDto');
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

  test('apiKey must start with tal_live_', () {
    expect(
      () => TalariaOptions(
        dsn: 'https://api.example.com',
        apiKey: 'wrong',
        environment: 'production',
      ),
      throwsArgumentError,
    );
  });
}
