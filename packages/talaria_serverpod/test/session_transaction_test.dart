import 'package:talaria/src/transport/fake_transport.dart';
import 'package:talaria/talaria.dart';
import 'package:talaria_serverpod/src/session_transaction.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    SpanScope.clearSessions();
    await Talaria.reset();
  });

  TalariaClient client(FakeTransport transport) {
    return TalariaClient(
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
  }

  test('FutureCall always starts a CONSUMER root', () async {
    final transport = FakeTransport();
    final c = client(transport);
    final leaked = c.startTransaction('lab/ping', kind: SpanKind.server);

    final result = SessionTransaction.bindOrStart(
      client: c,
      sessionId: 'fc-1',
      name: 'FutureCall.ProcessFulfillment',
      kind: SpanKind.consumer,
      attributes: {'serverpod.session.kind': 'futureCall'},
      isFutureCall: true,
    );

    expect(result.created, isTrue);
    expect(result.span.name, 'FutureCall.ProcessFulfillment');
    expect(result.span.kind, SpanKind.consumer);
    expect(result.span.spanId, isNot(leaked.spanId));
    expect(SpanScope.forSession('fc-1')?.spanId, result.span.spanId);

    leaked.finish();
    result.span.finish();
    await c.close();
  });

  test('does not adopt another session currentSpan outside a Relic zone',
      () async {
    final transport = FakeTransport();
    final c = client(transport);
    final stream = c.startTransaction('lab/ping', kind: SpanKind.server);

    final result = SessionTransaction.bindOrStart(
      client: c,
      sessionId: 'method-1',
      name: 'lab/slowQuery',
      kind: SpanKind.server,
      attributes: {'serverpod.session.kind': 'method'},
      isFutureCall: false,
    );

    expect(result.created, isTrue);
    expect(result.span.spanId, isNot(stream.spanId));

    stream.finish();
    result.span.finish();
    await c.close();
  });

  test('adopts Relic currentSpan only inside a zone for method sessions',
      () async {
    final transport = FakeTransport();
    final c = client(transport);

    await SpanScope.runAsync(() async {
      final relic = c.startTransaction('POST /lab/ping', kind: SpanKind.server);
      final result = SessionTransaction.bindOrStart(
        client: c,
        sessionId: 'rpc-1',
        name: 'lab/ping',
        kind: SpanKind.server,
        attributes: {'serverpod.session.kind': 'method'},
        isFutureCall: false,
      );
      expect(result.created, isFalse);
      expect(result.span.spanId, relic.spanId);
      relic.finish();
    });

    await c.close();
  });

  test('FutureCall inside a Relic zone still starts its own root', () async {
    final transport = FakeTransport();
    final c = client(transport);

    await SpanScope.runAsync(() async {
      final relic = c.startTransaction('POST /lab/ping', kind: SpanKind.server);
      final result = SessionTransaction.bindOrStart(
        client: c,
        sessionId: 'fc-2',
        name: 'FutureCall.ProcessFulfillment',
        kind: SpanKind.consumer,
        attributes: {'serverpod.session.kind': 'futureCall'},
        isFutureCall: true,
      );
      expect(result.created, isTrue);
      expect(result.span.spanId, isNot(relic.spanId));
      expect(result.span.kind, SpanKind.consumer);
      result.span.finish();
      relic.finish();
    });

    await c.close();
  });

  test('applyUser sets enduser.id on the session span', () async {
    final transport = FakeTransport();
    final c = client(transport);
    final result = SessionTransaction.bindOrStart(
      client: c,
      sessionId: 'user-sess',
      name: 'lab/list',
      kind: SpanKind.server,
      attributes: const {},
      isFutureCall: false,
      userId: 'auth-42',
    );
    expect(result.span.getAttribute('enduser.id'), 'auth-42');
    expect(result.span.getAttribute('user.id'), 'auth-42');
    result.span.finish();
    await c.flush();
    expect(transport.spanBatches.expand((b) => b).single.userId, 'auth-42');
    await c.close();
  });

  test('skips generic Serverpod diagnostic titles', () {
    expect(
      SessionTransaction.isGenericDiagnosticMessage(
        'Internal server error. Request handler failed with exception.',
      ),
      isTrue,
    );
    expect(
        SessionTransaction.isGenericDiagnosticMessage('StateError'), isFalse);
  });
}
