import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:talaria/src/transport/event_queue.dart';
import 'package:talaria/src/transport/fake_transport.dart';
import 'package:talaria/src/transport/ingest_backoff.dart';
import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

/// Rate limits (HTTP 429 + Retry-After) pause and retry; exhausted quotas
/// (HTTP 402) drop as `quota` and stop until reset; discard reports never
/// report on themselves.
final _t0 = DateTime.utc(2026, 10, 19, 1);

TransportException _rateLimited([int? seconds]) => TransportException(
      'HTTP 429',
      statusCode: 429,
      className: 'ApiRateLimitedException',
      retry: true,
      retryAfter: seconds == null ? null : Duration(seconds: seconds),
    );

TransportException _quota({String? meter, DateTime? resetAt, int? after}) =>
    TransportException(
      'HTTP 402',
      statusCode: 402,
      className: 'ApiQuotaExceededException',
      meter: meter,
      resetAt: resetAt,
      retryAfter: after == null ? null : Duration(seconds: after),
    );

void main() {
  group('HttpTransport error parsing', () {
    test('Retry-After as seconds or an HTTP date', () {
      expect(HttpTransport.retryAfterOf('30'), const Duration(seconds: 30));
      expect(
        HttpTransport.retryAfterOf('Mon, 19 Oct 2026 01:02:00 GMT', now: _t0),
        const Duration(minutes: 2),
      );
      expect(
        HttpTransport.retryAfterOf('Mon, 19 Oct 2026 00:00:00 GMT', now: _t0),
        Duration.zero,
      );
      expect(HttpTransport.retryAfterOf('soon'), isNull);
      expect(HttpTransport.retryAfterOf('-1'), isNull);
      expect(HttpTransport.retryAfterOf(null), isNull);
    });

    Future<TransportException> failWith(http.Response response) async {
      final transport = HttpTransport(
        url: 'http://localhost:8080',
        apiKey:
            'tal_sk_test_nz1_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg3B299S',
        httpClient: MockClient((_) async => response),
      );
      try {
        await transport.sendSpanBatch([_span()]);
      } on TransportException catch (e) {
        return e;
      }
      fail('expected a TransportException');
    }

    test('429 is a rate limit with its Retry-After', () async {
      final e = await failWith(
        http.Response(
          jsonEncode({
            'code': 'rate_limited',
            'detail': 'Too many requests',
            'retryAfterSeconds': 42,
          }),
          429,
          headers: {'retry-after': '37'},
        ),
      );
      expect(e.isRateLimited, isTrue);
      expect(e.isTransient, isTrue);
      expect(e.isQuotaExceeded, isFalse);
      expect(e.retryAfter, const Duration(seconds: 37), reason: 'header wins');
    });

    test('a 429 without the header falls back to retryAfterSeconds', () async {
      final e = await failWith(
        http.Response(
          jsonEncode({
            'code': 'rate_limited',
            'detail': 'slow down',
            'retryAfterSeconds': 42,
          }),
          429,
        ),
      );
      expect(e.retryAfter, const Duration(seconds: 42));
    });

    test(
      '402 is a quota with its meter and reset time, never transient',
      () async {
        final e = await failWith(
          http.Response(
            jsonEncode({
              'code': 'quota_exceeded',
              'detail': 'Monthly span quota reached',
              'meter': 'spans',
              'resetAt': '2026-11-01T00:00:00.000Z',
            }),
            402,
            headers: {'retry-after': '1000'},
          ),
        );
        expect(e.isQuotaExceeded, isTrue);
        expect(e.isTransient, isFalse);
        expect(e.meter, 'spans');
        expect(e.resetAt, DateTime.utc(2026, 11));
      },
    );
  });

  group('IngestBackoff', () {
    late DateTime now;
    IngestBackoff backoff() =>
        IngestBackoff(clock: () => now, random: Random(7));
    setUp(() => now = _t0);

    test('429 waits at least Retry-After, plus at most 20% jitter', () {
      final b = backoff();
      final outcome = b.onFailure(_rateLimited(30));
      expect(outcome.reason, DiscardReason.rateLimited);
      expect(outcome.requeue, isTrue);
      final left = b.remaining!;
      expect(left >= const Duration(seconds: 30), isTrue);
      expect(left <= const Duration(seconds: 36), isTrue);
      now = now.add(const Duration(seconds: 29));
      expect(b.isPaused, isTrue);
      now = now.add(const Duration(seconds: 8));
      expect(b.isPaused, isFalse);
    });

    test('repeated failures grow exponentially up to the cap', () {
      final b = backoff();
      final waits = <int>[];
      for (var i = 0; i < 12; i++) {
        b.onFailure(_rateLimited());
        waits.add(b.remaining!.inMilliseconds);
        now = now.add(b.remaining! + const Duration(milliseconds: 1));
      }
      // 1 s, 2 s, 4 s ... each plus up to 20%.
      for (var i = 0; i < 8; i++) {
        final base = 1000 * (1 << i);
        expect(waits[i], inInclusiveRange(base, (base * 1.2).round()));
      }
      expect(waits.last, inInclusiveRange(300000, 360000), reason: '5 min cap');
      b.onSuccess();
      b.onFailure(_rateLimited());
      expect(b.remaining!.inMilliseconds, inInclusiveRange(1000, 1200));
    });

    test('5xx and network errors back off with jitter and drop as network', () {
      final b = backoff();
      final outcome = b.onFailure(
        TransportException('HTTP 503', statusCode: 503),
      );
      expect(outcome.reason, DiscardReason.network);
      expect(outcome.requeue, isFalse);
      expect(b.remaining!.inMilliseconds, inInclusiveRange(500, 1000));
      expect(b.pauseReason, DiscardReason.network);
      b.onFailure(TransportException('socket closed'));
      expect(b.remaining!.inMilliseconds, inInclusiveRange(1000, 2000));
    });

    test('validation errors are not retried and do not pause', () {
      final b = backoff();
      final outcome = b.onFailure(
        TransportException(
          'HTTP 400',
          statusCode: 400,
          className: 'ApiValidationException',
        ),
      );
      expect(outcome.reason, DiscardReason.network);
      expect(b.isPaused, isFalse);
    });

    test('402 pauses until the reset, capped at an hour, else 10 minutes', () {
      final b = backoff();
      final outcome = b.onFailure(
        _quota(resetAt: _t0.add(const Duration(minutes: 20))),
      );
      expect(outcome.reason, DiscardReason.quota);
      expect(outcome.requeue, isFalse);
      expect(b.remaining, const Duration(minutes: 20));
      expect(b.refuseReason, DiscardReason.quota);

      final far = backoff()..onFailure(_quota(resetAt: DateTime.utc(2026, 11)));
      expect(far.remaining, const Duration(hours: 1));

      final header = backoff()..onFailure(_quota(after: 90));
      expect(header.remaining, const Duration(seconds: 90));

      final unknown = backoff()..onFailure(_quota());
      expect(unknown.remaining, const Duration(minutes: 10));
    });

    test('a short rate limit never cuts a quota pause short', () {
      final b = backoff()..onFailure(_quota());
      b.onFailure(_rateLimited(5));
      expect(b.pauseReason, DiscardReason.quota);
      expect(b.remaining, const Duration(minutes: 10));
    });
  });

  group('EventQueue with backoff', () {
    late DateTime now;
    late _ScriptedTransport transport;
    late List<(int, String)> discards;
    late IngestBackoff backoff;

    EventQueue queue({int maxBufferSize = 200}) => EventQueue(
          transport: transport,
          maxBatchSize: 10,
          maxBufferSize: maxBufferSize,
          flushIntervalMs: 0,
          clock: () => now,
          backoff: backoff,
          onDiscard: (count, reason) => discards.add((count, reason)),
        );

    setUp(() {
      now = _t0;
      transport = _ScriptedTransport();
      discards = [];
      backoff = IngestBackoff(clock: () => now, random: Random(1));
    });

    test(
      'a rate-limited batch is held, then sent once the pause is over',
      () async {
        final q = queue();
        transport.eventFailures.add(_rateLimited(10));
        q.enqueue(_event('a'));
        q.enqueue(_event('b'));
        await q.flush();
        expect(transport.eventsSent, isEmpty);
        expect(transport.eventAttempts, 1);
        expect(q.count, 2, reason: 'requeued, not dropped');
        expect(discards, isEmpty);

        await q.flush();
        expect(transport.eventAttempts, 1, reason: 'paused: no request');

        now = now.add(const Duration(seconds: 13));
        await q.flush();
        expect(transport.eventsSent.single.map((e) => e.message), ['a', 'b']);
        expect(backoff.isPaused, isFalse);
      },
    );

    test(
      'a buffer that fills behind a rate limit drops as rate_limited',
      () async {
        final q = queue(maxBufferSize: 3);
        transport.eventFailures.add(_rateLimited(10));
        for (final m in ['a', 'b', 'c']) {
          q.enqueue(_event(m));
        }
        await q.flush();
        q.enqueue(_event('d'));
        expect(discards, [(1, DiscardReason.rateLimited)]);
      },
    );

    test(
      'a 402 drops the batch as quota and refuses new events until reset',
      () async {
        final q = queue();
        transport.eventFailures.add(
          _quota(meter: 'events', resetAt: _t0.add(const Duration(minutes: 5))),
        );
        q.enqueue(_event('a'));
        await q.flush();
        expect(discards, [(1, DiscardReason.quota)]);
        expect(q.count, 0, reason: 'not retried');

        q.enqueue(_event('b'));
        expect(discards.last, (1, DiscardReason.quota));
        expect(q.count, 0);

        now = now.add(const Duration(minutes: 5, seconds: 1));
        q.enqueue(_event('c'));
        await q.flush();
        expect(transport.eventsSent.single.single.message, 'c');
        expect(transport.eventAttempts, 2);
      },
    );

    test('close while paused counts what is still held', () async {
      final q = queue();
      transport.eventFailures.add(_rateLimited(30));
      q.enqueue(_event('a'));
      await q.flush();
      await q.close();
      expect(discards, [(1, DiscardReason.rateLimited)]);
      expect(q.count, 0);
    });
  });

  group('TalariaClient', () {
    late DateTime now;
    late _ScriptedTransport transport;

    TalariaOptions options() => TalariaOptions(
          url: 'https://api.example.com',
          apiKey:
              'tal_sk_test_nz1_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg3B299S',
          defaultIntegrations: false,
          flushIntervalMs: 0,
        )..applySdkDocument({
            'schemaVersion': 1,
            'active': true,
            'tracing': {'enabled': true, 'tracesSampleRate': 0.0},
          });

    setUp(() {
      now = _t0;
      transport = _ScriptedTransport();
    });

    test(
      '429 then 402: spans held then dropped as quota; errors still sampled',
      () async {
        final client = TalariaClient(
          options(),
          transport: transport,
          clock: () => now,
        );
        transport.spanFailures.add(_rateLimited(5));
        // tracesSampleRate is 0, so only error spans are kept.
        client.startTransaction('GET /ok').finish();
        client
            .startTransaction('GET /boom')
            .finish(status: SpanStatus.error, statusMessage: 'boom');
        await client.flush();
        expect(transport.spanAttempts, 1);
        expect(transport.discardRows, isEmpty, reason: 'held, not dropped');

        now = now.add(const Duration(seconds: 7));
        transport.spanFailures.add(_quota(meter: 'spans'));
        await client.flush();
        expect(transport.spanAttempts, 2, reason: 'the held span was retried');
        expect(transport.discardRows, contains(('spans', 'quota', 1)));
        expect(
          transport.discardRows.where((r) => r.$2 == DiscardReason.network),
          isEmpty,
        );
        await client.close();
      },
    );

    test('a 402 naming another meter pauses that meter too', () async {
      final client = TalariaClient(
        options(),
        transport: transport,
        clock: () => now,
      );
      transport.eventFailures.add(_quota(meter: 'spans'));
      await client.captureMessage('over quota');
      await client.flush();
      client
          .startTransaction('GET /boom')
          .finish(status: SpanStatus.error, statusMessage: 'boom');
      await client.flush();
      expect(transport.spanAttempts, 0);
      expect(
        transport.discardRows,
        containsAll([('events', 'quota', 1), ('spans', 'quota', 1)]),
      );
      expect(client.isEventsIngestDisabled, isFalse);
      await client.close();
    });

    test(
      'a failed or rate-limited reportDiscards makes no spans or errors',
      () async {
        final reported = <Object>[];
        final client = TalariaClient(
          options(),
          transport: transport,
          clock: () => now,
          onTransportError: (e, [_]) => reported.add(e),
        );
        transport.eventFailures.add(_quota(meter: 'events'));
        await client.captureMessage('dropped');
        transport.discardFailures.addAll([
          _rateLimited(20),
          TransportException('HTTP 500', statusCode: 500),
        ]);
        // A request span is open while the discard report fails.
        final span = client.startTransaction('GET /in-flight');
        await client.flush();
        expect(transport.discardAttempts, 1);
        reported.clear();

        // Paused: no report is attempted.
        await client.flush();
        expect(transport.discardAttempts, 1);

        now = now.add(const Duration(seconds: 25));
        await client.flush(); // 500
        expect(transport.discardAttempts, 2);
        now = now.add(const Duration(seconds: 3));
        await client.flush();
        expect(transport.discardAttempts, 3);
        expect(transport.discardRows, [('events', 'quota', 1)]);

        span.finish();
        await client.flush();
        expect(
          transport.spanBatches,
          isEmpty,
          reason: 'sampled out; the discard failures added no spans',
        );
        expect(reported, isEmpty, reason: 'discard failures are not surfaced');
        expect(transport.eventsSent, isEmpty);
        expect(transport.discardRows.where((r) => r.$1 == 'discards'), isEmpty);
        await client.close();
      },
    );

    test(
      'a server without the new reasons still gets the legacy ones',
      () async {
        final client = TalariaClient(
          options(),
          transport: transport,
          clock: () => now,
        );
        transport.eventFailures.add(_quota(meter: 'events'));
        transport.spanFailures.add(
          TransportException('HTTP 503', statusCode: 503),
        );
        await client.captureMessage('over quota');
        client
            .startTransaction('GET /boom')
            .finish(status: SpanStatus.error, statusMessage: 'boom');
        transport.discardFailures.add(
          TransportException(
            'HTTP 400',
            statusCode: 400,
            className: 'ApiValidationException',
            bodyMessage: 'Unknown discard signal or reason',
          ),
        );
        await client.flush();
        expect(transport.discardAttempts, 2, reason: 'one legacy-only retry');
        expect(transport.discardRows, [('spans', 'network', 1)]);

        // Later quota drops are no longer sent to this server at all.
        await client.captureMessage('still over quota');
        await client.flush();
        expect(transport.discardAttempts, 2);
        await client.close();
      },
    );

    test('close sends what a pause still holds as a discard row', () async {
      final client = TalariaClient(
        options(),
        transport: transport,
        clock: () => now,
      );
      transport.eventFailures.add(_rateLimited(60));
      await client.captureMessage('held');
      await client.flush();
      expect(transport.discardRows, isEmpty);
      await client.close();
      expect(transport.discardRows, [('events', 'rate_limited', 1)]);
    });
  });
}

FinishedSpan _span() => FinishedSpan(
      traceId: '0' * 31 + '1',
      spanId: '0' * 15 + '2',
      name: 'GET /x',
      kind: SpanKind.server,
      startTime: _t0,
      endTime: _t0.add(const Duration(milliseconds: 1)),
    );

Event _event(String message) => Event(
      message: message,
      level: SeverityLevel.error,
      timestamp: _t0.toIso8601String(),
    );

/// Fails each call with the next scripted error, then succeeds.
class _ScriptedTransport extends FakeTransport {
  final List<TransportException> eventFailures = [];
  final List<TransportException> spanFailures = [];
  final List<TransportException> discardFailures = [];
  int eventAttempts = 0;
  int spanAttempts = 0;
  int discardAttempts = 0;
  final List<List<Event>> eventsSent = [];
  final List<(String, String, int)> discardRows = [];

  @override
  Future<void> sendBatch(List<Event> events) async {
    eventAttempts++;
    if (eventFailures.isNotEmpty) throw eventFailures.removeAt(0);
    eventsSent.add(List.of(events));
    await super.sendBatch(events);
  }

  @override
  Future<void> sendSpanBatch(List<FinishedSpan> spans) async {
    spanAttempts++;
    if (spanFailures.isNotEmpty) throw spanFailures.removeAt(0);
    await super.sendSpanBatch(spans);
  }

  @override
  Future<void> reportDiscards(List<DiscardRow> discards) async {
    discardAttempts++;
    if (discardFailures.isNotEmpty) throw discardFailures.removeAt(0);
    for (final row in discards) {
      discardRows.add((row.signal, row.reason, row.count));
    }
    await super.reportDiscards(discards);
  }
}
