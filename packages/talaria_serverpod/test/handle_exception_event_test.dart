import 'package:serverpod/serverpod.dart';
import 'package:talaria/src/transport/fake_transport.dart';
import 'package:talaria_serverpod/talaria_serverpod.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    await Talaria.reset();
    SpanScope.clearSessions();
    BreadcrumbScope.clearSessions();
    RuntimeContext.clearCurrent();
    TalariaServerpod.clearSessionUsersForTest();
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

  test('dogfood capture keeps rejected API calls and drops socket noise',
      () async {
    final transport = FakeTransport();
    await TalariaServerpod.init(
      TalariaOptions(
        dsn: 'https://api.example.com',
        apiKey: 'tal_live_test_key_for_unit_tests',
        defaultIntegrations: false,
        flushIntervalMs: 0,
      ),
      transport: transport,
    );
    TalariaServerpod.captureRejectedRequests = true;

    for (final message in [
      'Invalid API key',
      'API key expired',
      'Project access denied',
      'Project not found',
      'Ingest rate limit exceeded (100/min)',
      'Transaction spending cap reached',
    ]) {
      TalariaServerpod.handleExceptionEvent(
        ExceptionEvent(
          _ApiUnauthorizedException(),
          StackTrace.current,
          message: message,
        ),
      );
    }
    TalariaServerpod.handleExceptionEvent(
      ExceptionEvent(
        _WebSocketConnectionClosed(),
        StackTrace.current,
        message: 'WebSocketConnectionClosed: Connection closed. cr: done',
      ),
    );
    await drain();

    final titles = transport.batches
        .expand((b) => b)
        .map((event) => event.title)
        .toList();
    expect(titles, [
      'Invalid API key',
      'API key expired',
      'Project access denied',
      'Project not found',
      'Ingest rate limit exceeded (100/min)',
      'Transaction spending cap reached',
    ]);
  });

  test('handleExceptionEvent drops known ApiUnauthorizedException noise',
      () async {
    final transport = FakeTransport();
    await TalariaServerpod.init(
      TalariaOptions(
        dsn: 'https://api.example.com',
        apiKey: 'tal_live_test_key_for_unit_tests',
        defaultIntegrations: false,
        flushIntervalMs: 0,
      ),
      transport: transport,
    );

    for (final message in [
      'Invalid API key',
      'API key expired',
      'Project access denied',
    ]) {
      TalariaServerpod.handleExceptionEvent(
        ExceptionEvent(
          _ApiUnauthorizedException(),
          StackTrace.current,
          message: message,
        ),
      );
    }
    await drain();
    expect(transport.batches, isEmpty);
  });

  test(
    'handleExceptionEvent reports unexpected ApiUnauthorizedException',
    () async {
      final transport = FakeTransport();
      await TalariaServerpod.init(
        TalariaOptions(
          dsn: 'https://api.example.com',
          apiKey: 'tal_live_test_key_for_unit_tests',
          defaultIntegrations: false,
          flushIntervalMs: 0,
        ),
        transport: transport,
      );

      TalariaServerpod.handleExceptionEvent(
        ExceptionEvent(
          _ApiUnauthorizedException(),
          StackTrace.current,
          message: 'Ingest requires an API key',
        ),
      );
      await drain();

      final events = transport.batches.expand((b) => b).toList();
      expect(events, hasLength(1));
      expect(events.single.title, 'Ingest requires an API key');
    },
  );

  test('handleExceptionEvent drops WebSocketConnectionClosed', () async {
    final transport = FakeTransport();
    await TalariaServerpod.init(
      TalariaOptions(
        dsn: 'https://api.example.com',
        apiKey: 'tal_live_test_key_for_unit_tests',
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

  test('handleExceptionEvent drops quota and rate-limit control flow',
      () async {
    final transport = FakeTransport();
    await TalariaServerpod.init(
      TalariaOptions(
        dsn: 'https://api.example.com',
        apiKey: 'tal_live_test_key_for_unit_tests',
        defaultIntegrations: false,
        flushIntervalMs: 0,
      ),
      transport: transport,
    );

    TalariaServerpod.handleExceptionEvent(
      ExceptionEvent(
        _ApiQuotaExceededException(),
        StackTrace.current,
        message: 'Transaction spending cap reached',
      ),
    );
    TalariaServerpod.handleExceptionEvent(
      ExceptionEvent(
        StateError('limited'),
        StackTrace.current,
        message: 'Ingest rate limit exceeded (100/min)',
      ),
    );
    TalariaServerpod.handleExceptionEvent(
      ExceptionEvent(
        _ApiNotFoundException(),
        StackTrace.current,
        message: 'Project not found',
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

  test('title uses the exception message instead of a generated class',
      () async {
    final transport = FakeTransport();
    await TalariaServerpod.init(
      TalariaOptions(
        dsn: 'https://api.example.com',
        apiKey: 'tal_live_test_key_for_unit_tests',
        defaultIntegrations: false,
        flushIntervalMs: 0,
      ),
      transport: transport,
    );

    TalariaServerpod.handleExceptionEvent(
      ExceptionEvent(
        _BoomImpl(),
        StackTrace.current,
        message: '_BoomImpl',
      ),
    );
    await drain();
    final events = transport.batches.expand((b) => b).toList();
    expect(events.single.title, 'Invalid API key');
  });

  test('diagnostic capture ignores another request URL, crumbs, and span',
      () async {
    final transport = FakeTransport();
    final options = TalariaOptions(
      dsn: 'https://api.example.com',
      apiKey: 'tal_live_test_key_for_unit_tests',
      defaultIntegrations: false,
      flushIntervalMs: 0,
    );
    options.enableTracing = true;
    options.tracesSampleRate = 1;
    final client = await TalariaServerpod.init(options, transport: transport);

    const sessionId = '550e8400-e29b-41d4-a716-446655440000';
    final foreign = client.startTransaction(
      'GET /replays/start',
      kind: SpanKind.server,
    );
    final sessionSpan = client.startTransaction(
      'POST /events/ingestBatch',
      kind: SpanKind.server,
    );
    SpanScope.bindSession(sessionId, sessionSpan);
    final sessionCrumbs = BreadcrumbBuffer();
    sessionCrumbs.add(
      Breadcrumb(type: 'http', category: 'http', message: 'POST /events'),
    );
    BreadcrumbScope.bindSession(sessionId, sessionCrumbs);
    client.addBreadcrumb(
      Breadcrumb(type: 'http', category: 'http', message: 'GET /replays/start'),
    );
    RuntimeContext.setUrl('https://api.newtalaria.com/replays/start');
    RuntimeContext.setUserId('other-user');

    await RuntimeContext.runWithAsync(
      () async {
        await BreadcrumbScope.runWithAsync(
          () async {
            client.addBreadcrumb(
              Breadcrumb(
                type: 'http',
                category: 'http',
                message: 'GET /replays/start zone',
              ),
            );
            TalariaServerpod.handleExceptionEvent(
              ExceptionEvent(StateError('ingest'), StackTrace.current),
              context: MethodCallOpContext(
                serverName: 'api',
                serverId: 'srv',
                serverRunMode: 'test',
                sessionId: UuidValue.fromString(sessionId),
                uri: Uri.parse(
                  'https://api.newtalaria.com/events/ingestBatch',
                ),
                endpoint: 'events',
                methodName: 'ingestBatch',
              ),
            );
            await drain();
          },
          buffer: BreadcrumbBuffer(),
        );
      },
      url: 'https://api.newtalaria.com/replays/start',
      userId: 'other-user',
    );

    final events = transport.batches.expand((b) => b).toList();
    expect(events, hasLength(1));
    final event = events.single;
    expect(event.url, 'https://api.newtalaria.com/events/ingestBatch');
    expect(event.userId, isNot('other-user'));
    expect(event.traceId, sessionSpan.traceId);
    expect(event.traceId, isNot(foreign.traceId));
    final messages = event.breadcrumbs?.map((c) => c['message']).toList();
    expect(messages, ['POST /events']);
  });

  test('diagnostic event uses the session user, not another request', () async {
    final transport = FakeTransport();
    await TalariaServerpod.init(
      TalariaOptions(
        dsn: 'https://api.example.com',
        apiKey: 'tal_live_test_key_for_unit_tests',
        defaultIntegrations: false,
        flushIntervalMs: 0,
      ),
      transport: transport,
    );

    const sessionId = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';
    TalariaServerpod.bindSessionUser(
      '6ba7b811-9dad-11d1-80b4-00c04fd430c8',
      'other-user',
    );
    TalariaServerpod.bindSessionUser(sessionId, 'user-123');
    RuntimeContext.setUserId('isolate-user');

    await RuntimeContext.runWithAsync(
      () async {
        TalariaServerpod.handleExceptionEvent(
          ExceptionEvent(StateError('denied'), StackTrace.current),
          context: MethodCallOpContext(
            serverName: 'api',
            serverId: 'srv',
            serverRunMode: 'test',
            sessionId: UuidValue.fromString(sessionId),
            uri: Uri.parse('https://api.example.com/project/get'),
            endpoint: 'project',
            methodName: 'get',
          ),
        );
        await drain();
      },
      url: 'https://api.example.com/replays/start',
      userId: 'zone-user',
    );

    final event = transport.batches.expand((b) => b).single;
    expect(event.userId, 'user-123');
    expect(event.url, 'https://api.example.com/project/get');
  });

  test('diagnostic without a request URL does not inherit the isolate URL',
      () async {
    final transport = FakeTransport();
    final options = TalariaOptions(
      dsn: 'https://api.example.com',
      apiKey: 'tal_live_test_key_for_unit_tests',
      defaultIntegrations: false,
      flushIntervalMs: 0,
    );
    options.enableTracing = true;
    options.tracesSampleRate = 1;
    final client = await TalariaServerpod.init(options, transport: transport);

    client.startTransaction('GET /replays/start', kind: SpanKind.server);
    client.addBreadcrumb(
      Breadcrumb(type: 'http', category: 'http', message: 'GET /replays/start'),
    );
    RuntimeContext.setUrl('https://api.newtalaria.com/replays/start');

    TalariaServerpod.handleExceptionEvent(
      ExceptionEvent(StateError('orphan'), StackTrace.current),
      context: const DiagnosticEventContext(
        serverName: 'api',
        serverId: 'srv',
        serverRunMode: 'test',
      ),
    );
    await drain();

    final event = transport.batches.expand((b) => b).single;
    expect(event.url, isNull);
    expect(event.traceId, isNull);
    expect(event.breadcrumbs, isNull);
  });

  test('handleExceptionEvent copies caller org and project tags', () async {
    final transport = FakeTransport();
    await TalariaServerpod.init(
      TalariaOptions(
        dsn: 'https://api.example.com',
        apiKey: 'tal_live_test_key_for_unit_tests',
        defaultIntegrations: false,
        flushIntervalMs: 0,
      ),
      transport: transport,
    );
    const sessionId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    TalariaServerpod.bindSessionTags(sessionId, {
      'caller.organization_name': 'Ngai Tahu',
      'caller.project_name': 'Silverstripe',
      'caller.api_key_prefix': 'tal_live_abc',
      'caller.api_key_secret': '',
    });

    TalariaServerpod.handleExceptionEvent(
      ExceptionEvent(
        StateError('API key lacks required scope: monitors:write'),
        StackTrace.current,
      ),
      context: MethodCallOpContext(
        serverName: 'api',
        serverId: 'srv',
        serverRunMode: 'production',
        sessionId: UuidValue.fromString(sessionId),
        uri: Uri.parse('https://ingest.newtalaria.com/monitors/checkIn'),
        endpoint: 'monitors',
        methodName: 'checkIn',
      ),
    );
    await drain();

    final event = transport.batches.expand((b) => b).single;
    expect(event.tags?['caller.organization_name'], 'Ngai Tahu');
    expect(event.tags?['caller.project_name'], 'Silverstripe');
    expect(event.tags?['caller.api_key_prefix'], 'tal_live_abc');
    expect(event.tags?.containsKey('caller.api_key_secret'), isFalse);
  });
}

class _BoomImpl implements Exception {
  @override
  String toString() => 'Invalid API key';
}

class _ApiUnauthorizedException implements Exception {}

class _ApiQuotaExceededException implements Exception {}

class _ApiNotFoundException implements Exception {}

class _WebSocketConnectionClosed implements Exception {}
