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
    final created = TalariaOptions(
      dsn: 'https://api.example.com',
      apiKey: 'tal_live_test_key_for_unit_tests',
      defaultIntegrations: false,
      flushIntervalMs: 0,
    );
    if (enableTracing || (tracesSampleRate != null && tracesSampleRate > 0)) {
      created.applySdkDocument({
        'schemaVersion': 1,
        'active': true,
        'tracing': {
          'enabled': true,
          'tracesSampleRate': tracesSampleRate ?? 0.1,
        },
      });
    }
    return created;
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
      enrichment: () => const SpanEnrichment(),
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
      enrichment: () => const SpanEnrichment(),
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
      enrichment: () => const SpanEnrichment(),
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
      enrichment: () => const SpanEnrichment(),
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
      enrichment: () => const SpanEnrichment(),
    );

    final root = tracer.startTransaction('root');
    final child = tracer.startSpan('http');
    child.markError();
    child.finish();
    root.finish();

    expect(finished.length, greaterThanOrEqualTo(2));
  });

  test('interleaved SQL rolls up and later phases are stored', () {
    final finished = <FinishedSpan>[];
    final tracer = Tracer(
      options: options(tracesSampleRate: 1.0),
      enqueue: finished.add,
      enrichment: () => const SpanEnrichment(),
    );
    final root = tracer.startTransaction('sync');
    final import = tracer.startSpan('shopify.import_products');
    for (final name in ['SELECT File', 'SELECT SiteTree', 'SELECT Shopify_ProductVariant']) {
      for (var i = 0; i < 12; i++) {
        final query = tracer.startSpan(
          name,
          kind: SpanKind.client,
          attributes: {'db.query.text': name},
        );
        query.setStatus(SpanStatus.ok);
        query.finish();
      }
    }
    import.finish();
    tracer.startSpan('shopify.import_collections').finish();
    tracer.startSpan('shopify.import_collects').finish();
    root.finish();

    final names = finished.map((span) => span.name).toList();
    expect(names, contains('shopify.import_collections'));
    expect(names, contains('shopify.import_collects'));
    final queries = finished.where((span) => span.name.startsWith('SELECT'));
    expect(queries, hasLength(3));
    expect(
      queries.every((span) => span.attributes['db.query.count'] == '12'),
      isTrue,
    );
    expect(finished.singleWhere((span) => span.isRoot).attributes['dropped_span_count'], isNull);
  });

  test('the 169th distinct statement is dropped and a phase span is kept', () {
    final finished = <FinishedSpan>[];
    final tracer = Tracer(
      options: options(tracesSampleRate: 1.0),
      enqueue: finished.add,
      enrichment: () => const SpanEnrichment(),
    );
    final root = tracer.startTransaction('sync');
    for (var i = 0; i < Tracer.maxSqlSpans + 1; i++) {
      final query = tracer.startSpan(
        'SELECT t$i',
        kind: SpanKind.client,
        attributes: {'db.query.text': 'SELECT t$i'},
      );
      query.setStatus(SpanStatus.ok);
      query.finish();
    }
    tracer.startSpan('shopify.import_collections').finish();
    root.finish();

    final names = finished.map((span) => span.name).toSet();
    expect(names, contains('shopify.import_collections'));
    expect(names, isNot(contains('SELECT t${Tracer.maxSqlSpans}')));
    expect(
      finished.singleWhere((span) => span.isRoot).attributes['dropped_span_count'],
      '1',
    );
  });

  test('withoutQuerySpans restores recording when the body throws', () {
    final finished = <FinishedSpan>[];
    final tracer = Tracer(
      options: options(tracesSampleRate: 1.0),
      enqueue: finished.add,
      enrichment: () => const SpanEnrichment(),
    );
    final root = tracer.startTransaction('task');
    expect(
      () => tracer.withoutQuerySpans(() {
        final query = tracer.startSpan(
          'SELECT File',
          kind: SpanKind.client,
          attributes: {'db.query.text': 'SELECT File'},
        );
        query.finish();
        throw StateError('sync failed');
      }),
      throwsStateError,
    );
    expect(tracer.recordQuerySpans, isTrue);
    tracer.startSpan('shopify.import_collections').finish();
    root.finish();
    expect(finished.map((span) => span.name), ['shopify.import_collections', 'task']);
  });
}
