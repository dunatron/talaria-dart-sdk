import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:talaria/src/transport/fake_transport.dart';
import 'package:talaria/src/transport/ingest_backoff.dart';
import 'package:talaria/src/transport/span_queue.dart';
import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

/// Spans go out in batches on a size threshold or an interval, at most
/// `maxExportsPerMinute` automatic exports a minute, with a bounded buffer.
/// Before this, the Serverpod middleware flushed once per traced request.
final _start = DateTime.utc(2026, 10, 19);

FinishedSpan _span(int i) => FinishedSpan(
      traceId: i.toRadixString(16).padLeft(32, '0'),
      spanId: (i + 1).toRadixString(16).padLeft(16, '0'),
      name: 'GET /x/$i',
      kind: SpanKind.server,
      startTime: _start,
      endTime: _start.add(const Duration(milliseconds: 1)),
    );

int _spanCount(FakeTransport t) =>
    t.spanBatches.fold(0, (sum, b) => sum + b.length);

void main() {
  _backoffTests();

  test('a full batch is exported without waiting for the interval', () {
    fakeAsync((async) {
      final transport = FakeTransport();
      final queue = SpanQueue(
        transport: transport,
        maxBatchSize: 3,
        flushIntervalMs: 60000,
        clock: () => _start.add(async.elapsed),
      );
      queue.enqueue(_span(1));
      queue.enqueue(_span(2));
      async.flushMicrotasks();
      expect(transport.spanBatches, isEmpty);
      queue.enqueue(_span(3));
      async.flushMicrotasks();
      expect(transport.spanBatches.map((b) => b.length), [3]);
      expect(queue.count, 0);
    });
  });

  test('a partial batch goes out once the interval has passed', () {
    fakeAsync((async) {
      final transport = FakeTransport();
      final queue = SpanQueue(
        transport: transport,
        maxBatchSize: 100,
        flushIntervalMs: 5000,
        clock: () => _start.add(async.elapsed),
      );
      queue.enqueue(_span(1));
      async.elapse(const Duration(milliseconds: 4000));
      queue.enqueue(_span(2));
      async.elapse(const Duration(milliseconds: 999));
      expect(transport.spanBatches, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(transport.spanBatches.map((b) => b.length), [2]);
      expect(queue.hasPendingExport, isFalse, reason: 'idle: no timer');
    });
  });

  test('automatic exports are spaced to stay under the per-minute cap', () {
    fakeAsync((async) {
      final transport = FakeTransport();
      final queue = SpanQueue(
        transport: transport,
        maxBatchSize: 2,
        flushIntervalMs: 0,
        maxExportsPerMinute: 30,
        clock: () => _start.add(async.elapsed),
      );
      for (var i = 0; i < 10; i++) {
        queue.enqueue(_span(i));
      }
      async.flushMicrotasks();
      expect(transport.spanBatches, hasLength(1));
      async.elapse(const Duration(milliseconds: 1999));
      expect(transport.spanBatches, hasLength(1));
      async.elapse(const Duration(milliseconds: 1));
      expect(transport.spanBatches, hasLength(2));
      async.elapse(const Duration(seconds: 6));
      expect(transport.spanBatches, hasLength(5));
      expect(_spanCount(transport), 10);
    });
  });

  test('a busy minute with defaults stays well under 100 exports', () {
    fakeAsync((async) {
      final transport = FakeTransport();
      final queue = SpanQueue(
        transport: transport,
        clock: () => _start.add(async.elapsed),
      );
      // 20 finished spans a second for a minute (1200 spans).
      for (var i = 0; i < 1200; i++) {
        queue.enqueue(_span(i));
        async.elapse(const Duration(milliseconds: 50));
      }
      expect(transport.spanBatches.length, lessThanOrEqualTo(30));
      async.elapse(const Duration(seconds: 10));
      expect(_spanCount(transport), 1200, reason: 'nothing dropped');
    });
  });

  test('a full buffer drops new spans as queue_overflow', () {
    fakeAsync((async) {
      final transport = FakeTransport();
      final dropped = <String, int>{};
      final queue = SpanQueue(
        transport: transport,
        maxBatchSize: 100,
        maxBufferSize: 5,
        flushIntervalMs: 0,
        onDiscard: (n, reason) => dropped[reason] = (dropped[reason] ?? 0) + n,
        clock: () => _start.add(async.elapsed),
      );
      for (var i = 0; i < 8; i++) {
        queue.enqueue(_span(i));
      }
      expect(queue.count, 5);
      expect(dropped, {'queue_overflow': 3});
    });
  });

  test('flush sends everything now and waits for an export in flight', () {
    fakeAsync((async) {
      final transport = _GatedTransport();
      final queue = SpanQueue(
        transport: transport,
        maxBatchSize: 2,
        flushIntervalMs: 0,
        maxExportsPerMinute: 1,
        clock: () => _start.add(async.elapsed),
      );
      for (var i = 0; i < 7; i++) {
        queue.enqueue(_span(i));
      }
      async.flushMicrotasks();
      expect(transport.started, 1, reason: 'one automatic export started');
      var done = false;
      // ignore: discarded_futures
      queue.flush().then((_) => done = true);
      async.flushMicrotasks();
      expect(done, isFalse, reason: 'waits for the export in flight');
      transport.release();
      async.flushMicrotasks();
      expect(done, isTrue);
      expect(transport.sizes, [2, 2, 2, 1], reason: 'spacing ignored');
      expect(queue.count, 0);
    });
  });

  test('close leaves no timer armed and ignores later spans', () {
    fakeAsync((async) {
      final transport = FakeTransport();
      final queue = SpanQueue(
        transport: transport,
        maxBatchSize: 100,
        flushIntervalMs: 5000,
        clock: () => _start.add(async.elapsed),
      );
      queue.enqueue(_span(1));
      expect(queue.hasPendingExport, isTrue);
      // ignore: discarded_futures
      queue.close();
      async.flushMicrotasks();
      expect(transport.spanBatches.map((b) => b.length), [1]);
      expect(async.pendingTimers, isEmpty);
      queue.enqueue(_span(2));
      async.elapse(const Duration(minutes: 1));
      expect(transport.spanBatches, hasLength(1));
    });
  });

  test('filling the batch brings forward a pending interval export', () {
    fakeAsync((async) {
      final transport = FakeTransport();
      final queue = SpanQueue(
        transport: transport,
        maxBatchSize: 3,
        flushIntervalMs: 5000,
        clock: () => _start.add(async.elapsed),
      );
      queue.enqueue(_span(1));
      async.elapse(const Duration(seconds: 1));
      queue.enqueue(_span(2));
      queue.enqueue(_span(3));
      async.flushMicrotasks();
      expect(transport.spanBatches.map((b) => b.length), [3]);
    });
  });

  test('without timers a due batch goes out on the next span or a flush', () {
    fakeAsync((async) {
      final transport = FakeTransport();
      final queue = SpanQueue(
        transport: transport,
        maxBatchSize: 2,
        flushIntervalMs: 5000,
        timers: false,
        clock: () => _start.add(async.elapsed),
      );
      queue.enqueue(_span(1));
      expect(async.pendingTimers, isEmpty);
      async.elapse(const Duration(seconds: 6));
      expect(transport.spanBatches, isEmpty, reason: 'nothing to wake it');
      queue.enqueue(_span(2));
      async.flushMicrotasks();
      expect(transport.spanBatches.map((b) => b.length), [2]);
      queue.enqueue(_span(3));
      expect(async.pendingTimers, isEmpty);
      // ignore: discarded_futures
      queue.flush();
      async.flushMicrotasks();
      expect(transport.spanBatches.map((b) => b.length), [2, 1]);
    });
  });

  group('TalariaClient', () {
    TalariaOptions options({int flushIntervalMs = 2000}) => TalariaOptions(
          dsn: 'https://api.example.com',
          apiKey: 'tal_live_test_key_for_unit_tests',
          defaultIntegrations: false,
          flushIntervalMs: flushIntervalMs,
        )..applySdkDocument({
            'schemaVersion': 1,
            'active': true,
            'tracing': {'enabled': true, 'tracesSampleRate': 1.0},
          });

    test('span export defaults', () {
      final o = options();
      expect(o.spanBatchSize, 200);
      expect(o.spanFlushIntervalMs, 5000);
      expect(o.maxSpanExportsPerMinute, 30);
      expect(o.maxSpanQueueSize, 2048);
      final clamped = o.copyWith(
        spanBatchSize: 5000,
        maxSpanExportsPerMinute: 0,
        maxSpanQueueSize: 1,
      );
      expect(clamped.spanBatchSize, TalariaOptions.maxSpanBatchSize);
      expect(clamped.maxSpanExportsPerMinute, 1);
      expect(clamped.maxSpanQueueSize, TalariaOptions.maxSpanBatchSize);
    });

    test('100 traced requests a minute make a handful of span exports', () {
      fakeAsync((async) {
        final transport = FakeTransport();
        final client = TalariaClient(options(), transport: transport);
        for (var i = 0; i < 100; i++) {
          client.startTransaction('GET /r/$i', kind: SpanKind.server).finish();
          async.elapse(const Duration(milliseconds: 600));
        }
        async.elapse(const Duration(seconds: 6));
        // About one export per 5 s interval, not one per request.
        expect(transport.spanBatches.length, inInclusiveRange(10, 14));
        expect(_spanCount(transport), 100);
        // ignore: discarded_futures
        client.close();
        async.flushMicrotasks();
      });
    });

    test('explicit flush still sends pending spans at once', () async {
      final transport = FakeTransport();
      final client = TalariaClient(
        options(flushIntervalMs: 0),
        transport: transport,
      );
      client.startTransaction('GET /a').finish();
      client.startTransaction('GET /b').finish();
      expect(transport.spanBatches, isEmpty);
      expect(client.spanQueueSize(), 2);
      await client.flush();
      expect(transport.spanBatches.map((b) => b.length), [2]);
      await client.close();
    });

    test('flushIntervalMs: 0 starts no timers for spans', () {
      fakeAsync((async) {
        final transport = FakeTransport();
        final client = TalariaClient(
          options(flushIntervalMs: 0),
          transport: transport,
        );
        client.startTransaction('GET /a').finish();
        expect(async.pendingTimers, isEmpty);
        // ignore: discarded_futures
        client.close();
        async.flushMicrotasks();
        expect(_spanCount(transport), 1);
      });
    });

    test('close sends spans that were still waiting for their batch', () async {
      final transport = FakeTransport();
      final client = TalariaClient(options(), transport: transport);
      client.startTransaction('GET /late').finish();
      await client.close();
      expect(_spanCount(transport), 1);
    });
  });
}

/// Batching together with 429/402 backoff: a paused queue holds (or
/// refuses) spans, and the batch timer re-arms for the end of the pause.
void _backoffTests() {
  group('with backoff', () {
    TransportException rateLimited(int seconds) => TransportException(
          'HTTP 429',
          statusCode: 429,
          className: 'ApiRateLimitedException',
          retry: true,
          retryAfter: Duration(seconds: seconds),
        );

    test('a 429 holds the batch; it is resent after the pause, not before', () {
      fakeAsync((async) {
        final transport = _FailingTransport()..failures.add(rateLimited(30));
        final discards = <(int, String)>[];
        DateTime clock() => _start.add(async.elapsed);
        final queue = SpanQueue(
          transport: transport,
          maxBatchSize: 2,
          flushIntervalMs: 5000,
          clock: clock,
          backoff: IngestBackoff(clock: clock),
          onDiscard: (n, r) => discards.add((n, r)),
        );
        queue.enqueue(_span(1));
        queue.enqueue(_span(2));
        async.flushMicrotasks();
        expect(transport.attempts, 1);
        expect(queue.count, 2, reason: 'rate-limited batch is kept');
        expect(queue.hasPendingExport, isTrue,
            reason: 'timer armed for the end of the pause');

        // An explicit flush doesn't override the pause.
        // ignore: discarded_futures
        queue.flush();
        async.flushMicrotasks();
        expect(transport.attempts, 1);
        expect(queue.hasPendingExport, isTrue);

        async.elapse(const Duration(seconds: 29));
        expect(transport.attempts, 1);
        // Retry-After 30 s plus at most 20% jitter.
        async.elapse(const Duration(seconds: 8));
        expect(transport.attempts, 2);
        expect(_spanCount(transport), 2);
        expect(queue.count, 0);
        expect(discards, isEmpty);
      });
    });

    test('a 402 drops the batch as quota and refuses new spans', () {
      fakeAsync((async) {
        final transport = _FailingTransport()
          ..failures.add(TransportException(
            'HTTP 402',
            statusCode: 402,
            className: 'ApiQuotaExceededException',
            meter: 'spans',
            retryAfter: const Duration(minutes: 2),
          ));
        final discards = <(int, String)>[];
        DateTime clock() => _start.add(async.elapsed);
        final queue = SpanQueue(
          transport: transport,
          maxBatchSize: 2,
          clock: clock,
          backoff: IngestBackoff(clock: clock),
          onDiscard: (n, r) => discards.add((n, r)),
        );
        queue.enqueue(_span(1));
        queue.enqueue(_span(2));
        async.flushMicrotasks();
        queue.enqueue(_span(3));
        expect(discards, [(2, 'quota'), (1, 'quota')]);
        expect(queue.count, 0);
        async.elapse(const Duration(minutes: 3));
        queue.enqueue(_span(4));
        queue.enqueue(_span(5));
        async.flushMicrotasks();
        expect(_spanCount(transport), 2, reason: 'sends again after reset');
      });
    });

    test('close while paused counts held spans as rate_limited', () async {
      final transport = _FailingTransport()..failures.add(rateLimited(60));
      final discards = <(int, String)>[];
      final queue = SpanQueue(
        transport: transport,
        maxBatchSize: 1,
        backoff: IngestBackoff(),
        onDiscard: (n, r) => discards.add((n, r)),
      );
      queue.enqueue(_span(1));
      await Future<void>.delayed(Duration.zero);
      expect(queue.count, 1);
      await queue.close();
      expect(discards, [(1, 'rate_limited')]);
      expect(queue.count, 0);
      expect(queue.hasPendingExport, isFalse);
    });
  });
}

/// Fails span exports with [failures] in order, then succeeds.
class _FailingTransport extends FakeTransport {
  final failures = <TransportException>[];
  var attempts = 0;

  @override
  Future<void> sendSpanBatch(List<FinishedSpan> spans) async {
    attempts++;
    if (failures.isNotEmpty) throw failures.removeAt(0);
    await super.sendSpanBatch(spans);
  }
}

/// Holds every span export until [release].
class _GatedTransport extends FakeTransport {
  final sizes = <int>[];
  var started = 0;
  Completer<void>? _gate = Completer<void>();

  void release() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<void> sendSpanBatch(List<FinishedSpan> spans) async {
    started++;
    sizes.add(spans.length);
    final gate = _gate;
    if (gate != null) await gate.future;
  }
}
