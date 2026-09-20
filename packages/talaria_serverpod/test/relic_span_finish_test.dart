import 'package:talaria/src/transport/fake_transport.dart';
import 'package:talaria/talaria.dart';
import 'package:talaria_serverpod/src/relic_span_finish.dart';
import 'package:test/test.dart';

void main() {
  late TalariaClient client;
  late FakeTransport transport;

  setUp(() {
    transport = FakeTransport();
    client = TalariaClient(
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
  });

  tearDown(() async {
    await client.close();
  });

  test('onThrow sets HTTP 500 and error status', () {
    final span = client.startTransaction('POST /lab/uncaughtThrow');
    RelicSpanFinish.onThrow(span, StateError('boom'));
    expect(span.getAttribute('http.response.status_code'), '500');
    expect(span.status, SpanStatus.error);
    span.finish();
  });

  test('onResponse does not overwrite captureException error on HTTP 200', () {
    final span = client.startTransaction('POST /lab/handledException');
    span.markError(message: 'handled');
    RelicSpanFinish.onResponse(span, 200);
    expect(span.getAttribute('http.response.status_code'), '200');
    expect(span.status, SpanStatus.error);
    span.finish();
  });

  test('onResponse marks 5xx as error', () {
    final span = client.startTransaction('POST /lab/fail');
    RelicSpanFinish.onResponse(span, 500);
    expect(span.status, SpanStatus.error);
    span.finish();
  });
}
