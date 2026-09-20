import 'package:serverpod/serverpod.dart';
import 'package:talaria/src/transport/fake_transport.dart';
import 'package:talaria_serverpod/talaria_serverpod.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    await Talaria.reset();
  });

  test('handleExceptionEvent drops the generic wrapper event', () async {
    final transport = FakeTransport();
    await TalariaServerpod.init(
      TalariaOptions(
        dsn: 'https://api.example.com',
        apiKey: 'tal_live_test_key_for_unit_tests',
        environment: 'development',
        defaultIntegrations: false,
        flushIntervalMs: 0,
      ),
      transport: transport,
    );

    final error = StateError('uncaught');
    final stack = StackTrace.current;
    TalariaServerpod.handleExceptionEvent(
      ExceptionEvent(error, stack, message: 'StateError'),
    );
    TalariaServerpod.handleExceptionEvent(
      ExceptionEvent(
        error,
        stack,
        message:
            'Internal server error. Request handler failed with exception.',
      ),
    );
    await Talaria.flush();

    final events = transport.batches.expand((b) => b).toList();
    expect(events, hasLength(1));
    expect(events.single.title, 'StateError');
  });
}
