import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() {
    SpanScope.clearSessions();
  });

  TalariaOptions options() {
    return TalariaOptions(
      dsn: 'https://api.example.com',
      apiKey: 'tal_live_test_key_for_unit_tests',
      environment: 'development',
      tracesSampleRate: 1.0,
      defaultIntegrations: false,
      flushIntervalMs: 0,
    );
  }

  Tracer tracer(List<FinishedSpan> finished) {
    return Tracer(
      options: options(),
      enqueue: finished.add,
      enrichment: () => SpanEnrichment(environment: Environment.development),
    );
  }

  test('isolated zones keep concurrent current spans apart', () async {
    final finished = <FinishedSpan>[];
    final t = tracer(finished);

    late Span first;
    late Span second;

    final a = SpanScope.runAsync(() async {
      first = t.startTransaction('A');
      await Future<void>.delayed(Duration.zero);
      expect(t.currentSpan?.spanId, first.spanId);
      first.finish();
    });

    final b = SpanScope.runAsync(() async {
      second = t.startTransaction('B');
      await Future<void>.delayed(Duration.zero);
      expect(t.currentSpan?.spanId, second.spanId);
      second.finish();
    });

    await Future.wait([a, b]);
    expect(first.spanId, isNot(second.spanId));
    expect(finished.map((s) => s.name), containsAll(['A', 'B']));
  });

  test('session map is a fallback when the zone has no stack', () {
    final finished = <FinishedSpan>[];
    final t = tracer(finished);
    final root = t.startTransaction('root');
    SpanScope.bindSession('sess-1', root);
    expect(SpanScope.forSession('sess-1'), same(root));
    root.finish();
    expect(SpanScope.forSession('sess-1'), isNull);
    SpanScope.unbindSession('sess-1');
  });

  test('child spans in a zone nest under that zone root', () async {
    final finished = <FinishedSpan>[];
    final t = tracer(finished);

    await SpanScope.runAsync(() async {
      final root = t.startTransaction('http');
      final child = t.startSpan('db', kind: SpanKind.client);
      expect(child.parentSpanId, root.spanId);
      child.finish();
      root.finish();
    });

    expect(finished, hasLength(2));
  });
}
