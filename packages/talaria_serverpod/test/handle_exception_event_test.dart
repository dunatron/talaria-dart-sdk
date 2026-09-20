import 'package:serverpod/serverpod.dart';
import 'package:talaria/src/transport/fake_transport.dart';
import 'package:talaria_serverpod/talaria_serverpod.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    await Talaria.reset();
  });

  Future<void> drain() async {
    await Future<void>.delayed(Duration.zero);
    await Talaria.flush();
  }

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
    await drain();

    final events = transport.batches.expand((b) => b).toList();
    expect(events, hasLength(1));
    expect(events.single.title, 'StateError');
  });

  test('handleExceptionEvent drops ApiUnauthorizedException', () async {
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

    TalariaServerpod.handleExceptionEvent(
      ExceptionEvent(
        _ApiUnauthorizedException(),
        StackTrace.current,
        message: 'Invalid API key',
      ),
    );
    await drain();
    expect(transport.batches, isEmpty);
  });

  test('handleExceptionEvent drops WebSocketConnectionClosed', () async {
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

    TalariaServerpod.handleExceptionEvent(
      ExceptionEvent(
        _WebSocketConnectionClosed(),
        StackTrace.current,
        message: 'WebSocketConnectionClosed: Connection closed. cr: done',
      ),
    );
    await drain();
    expect(transport.batches, isEmpty);
  });

  test('handleExceptionEvent keeps TypeError', () async {
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

    TalariaServerpod.handleExceptionEvent(
      ExceptionEvent(TypeError(), StackTrace.current, message: 'TypeError'),
    );
    await drain();
    final events = transport.batches.expand((b) => b).toList();
    expect(events, hasLength(1));
    expect(events.single.title, 'TypeError');
  });

  test('handleExceptionEvent strips stream cid from titles', () async {
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

    TalariaServerpod.handleExceptionEvent(
      ExceptionEvent(
        StateError('stream'),
        StackTrace.current,
        message: 'Connection 550e8400-e29b-41d4-a716-446655440000 closed',
      ),
    );
    await drain();
    final events = transport.batches.expand((b) => b).toList();
    expect(events.single.title, 'Connection <id> closed');
  });

  test('concurrent captures do not leak URL or breadcrumbs', () async {
    final transport = FakeTransport();
    final client = await TalariaServerpod.init(
      TalariaOptions(
        dsn: 'https://api.example.com',
        apiKey: 'tal_live_test_key_for_unit_tests',
        environment: 'development',
        defaultIntegrations: false,
        flushIntervalMs: 0,
      ),
      transport: transport,
    );

    Future<void> capture(String url, String crumb) {
      return BreadcrumbScope.runWithAsync(
        () {
          return RuntimeContext.runWithAsync(
            () async {
              client.addBreadcrumb(
                Breadcrumb(type: 'http', category: 'http', message: crumb),
              );
              await client.captureException(StateError(crumb));
            },
            url: url,
          );
        },
        buffer: BreadcrumbBuffer(),
      );
    }

    await Future.wait([
      capture('https://a.example/one', 'GET /one'),
      capture('https://b.example/two', 'GET /two'),
    ]);
    await drain();

    final events = transport.batches.expand((b) => b).toList();
    expect(events, hasLength(2));
    final byUrl = {for (final e in events) e.url: e};
    expect(byUrl.keys,
        containsAll(['https://a.example/one', 'https://b.example/two']));
    expect(
      byUrl['https://a.example/one']!.breadcrumbs?.map((c) => c['message']),
      contains('GET /one'),
    );
    expect(
      byUrl['https://a.example/one']!.breadcrumbs?.map((c) => c['message']),
      isNot(contains('GET /two')),
    );
  });
}

class _ApiUnauthorizedException implements Exception {}

class _WebSocketConnectionClosed implements Exception {}
