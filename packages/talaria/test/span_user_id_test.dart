import 'package:talaria/src/transport/fake_transport.dart';
import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    RuntimeContext.setUserAgent(null);
    await Talaria.reset();
  });

  test('span user.id is copied onto finished spans and error events', () async {
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

    final span = client.startTransaction('POST /lab');
    span.setAttribute('enduser.id', 'user-9');
    span.setAttribute('user.id', 'user-9');
    await client.captureException(StateError('handled'));
    span.finish();
    await client.flush();

    expect(transport.batches.expand((b) => b).single.userId, 'user-9');
    expect(transport.spanBatches.expand((b) => b).single.userId, 'user-9');
    await client.close();
  });

  test('userAgent is copied onto events', () async {
    final transport = FakeTransport();
    RuntimeContext.setUserAgent('Mozilla/5.0 Test');
    final client = TalariaClient(
      TalariaOptions(
        dsn: 'https://api.example.com',
        apiKey: 'tal_live_test_key_for_unit_tests',
        environment: 'development',
        defaultIntegrations: false,
        flushIntervalMs: 0,
      ),
      transport: transport,
    );

    await client.captureException(StateError('ua'));
    await client.flush();

    expect(transport.batches.expand((b) => b).single.userAgent,
        'Mozilla/5.0 Test');
    await client.close();
  });
}
