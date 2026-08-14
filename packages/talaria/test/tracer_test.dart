import 'dart:math';

import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

class _FixedRandom implements Random {
  _FixedRandom(this._double);

  final double _double;

  @override
  double nextDouble() => _double;

  @override
  bool nextBool() => false;

  @override
  int nextInt(int max) => 1;
}

void main() {
  TalariaOptions options({
    bool enableTracing = false,
    double? tracesSampleRate,
  }) {
    return TalariaOptions(
      dsn: 'https://api.example.com',
      apiKey: 'tal_live_test_key_for_unit_tests',
      environment: 'development',
      enableTracing: enableTracing,
      tracesSampleRate: tracesSampleRate,
      defaultIntegrations: false,
      flushIntervalMs: 0,
    );
  }

  test('tracing is off by default', () {
    expect(options().isTracingEnabled, isFalse);
    expect(options(enableTracing: true).isTracingEnabled, isTrue);
    expect(options(tracesSampleRate: 0.2).isTracingEnabled, isTrue);
    expect(options(tracesSampleRate: 0.0).isTracingEnabled, isFalse);
  });

  test('startTransaction is no-op when tracing is off', () {
    final finished = <FinishedSpan>[];
    final tracer = Tracer(
      options: options(),
      enqueue: finished.add,
      enrichment: () => SpanEnrichment(environment: Environment.development),
    );

    final span = tracer.startTransaction('GET /x');
    expect(span.isRecording, isFalse);
    span.finish();
    expect(finished, isEmpty);
  });

  test('success transactions honor tracesSampleRate', () {
    final finished = <FinishedSpan>[];
    final tracer = Tracer(
      options: options(enableTracing: true, tracesSampleRate: 0.10),
      enqueue: finished.add,
      enrichment: () => SpanEnrichment(environment: Environment.development),
      random: _FixedRandom(0.99),
    );

    final span = tracer.startTransaction('ui');
    expect(span.isRecording, isTrue);
    span.setStatus(SpanStatus.ok);
    span.finish();
    expect(finished, isEmpty);
  });

  test('error transactions are always sampled', () {
    final finished = <FinishedSpan>[];
    final tracer = Tracer(
      options: options(enableTracing: true, tracesSampleRate: 0.10),
      enqueue: finished.add,
      enrichment: () => SpanEnrichment(environment: Environment.development),
      random: _FixedRandom(0.99),
    );

    final span = tracer.startTransaction('ui');
    span.markError(message: 'boom');
    span.finish();
    expect(finished, hasLength(1));
    expect(finished.single.status, SpanStatus.error);
    expect(finished.single.isRoot, isTrue);
  });

  test('child spans share trace id and cap at 200', () {
    final finished = <FinishedSpan>[];
    final tracer = Tracer(
      options: options(tracesSampleRate: 1.0),
      enqueue: finished.add,
      enrichment: () => SpanEnrichment(environment: Environment.development),
    );

    final root = tracer.startTransaction('root');
    final child = tracer.startSpan('child', kind: SpanKind.client);
    expect(child.traceId, root.traceId);
    expect(child.parentSpanId, root.spanId);
    child.finish();
    root.finish();

    expect(finished, hasLength(2));
    expect(finished.map((s) => s.name), containsAll(['root', 'child']));
  });

  test('error on child upgrades held unsampled tree', () {
    final finished = <FinishedSpan>[];
    final tracer = Tracer(
      options: options(enableTracing: true, tracesSampleRate: 0.0),
      enqueue: finished.add,
      enrichment: () => SpanEnrichment(environment: Environment.development),
    );

    final root = tracer.startTransaction('root');
    final child = tracer.startSpan('http');
    child.markError();
    child.finish();
    root.finish();

    expect(finished.length, greaterThanOrEqualTo(2));
  });
}
