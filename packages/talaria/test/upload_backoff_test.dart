import 'dart:convert';

import 'package:talaria/src/transport/fake_transport.dart';
import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

/// Heatmap uploads and flag reads aren't queued, so they back off in the
/// client: after a 429/402 they throw [IngestPausedException] without sending
/// until the pause ends, the way the event/span/analytics queues hold.
final _t0 = DateTime.utc(2026, 10, 19, 1);

TransportException _rateLimited(int seconds) => TransportException(
  'HTTP 429',
  statusCode: 429,
  className: 'ApiRateLimitedException',
  retry: true,
  retryAfter: Duration(seconds: seconds),
);

TransportException _quota({String? meter, DateTime? resetAt}) =>
    TransportException(
      'HTTP 402',
      statusCode: 402,
      className: 'ApiQuotaExceededException',
      meter: meter,
      resetAt: resetAt,
    );

Map<String, Object?> _view(String id) => {'screenViewId': id};

void main() {
  late DateTime now;
  late _UploadTransport transport;

  TalariaOptions options({bool flags = false}) =>
      TalariaOptions(
        url: 'https://api.example.com',
        apiKey: 'tal_prod_test_key_for_unit_tests',
        defaultIntegrations: false,
        flushIntervalMs: 0,
      )..applySdkDocument({
        'schemaVersion': 1,
        'active': true,
        'flags': {'enabled': flags},
        'tracing': {'enabled': true, 'tracesSampleRate': 1.0},
      });

  TalariaClient client({bool flags = false}) => TalariaClient(
    options(flags: flags),
    transport: transport,
    clock: () => now,
  );

  setUp(() {
    now = _t0;
    transport = _UploadTransport();
  });

  group('screen heatmaps', () {
    test(
      'a 429 pauses every heatmap upload for Retry-After plus jitter',
      () async {
        final c = client();
        transport.heatmapFailures.add(_rateLimited(30));
        await expectLater(
          c.sendScreenHeatmapBatch([_view('a')]),
          throwsA(
            isA<TransportException>().having(
              (e) => e.isRateLimited,
              'isRateLimited',
              isTrue,
            ),
          ),
        );
        expect(transport.heatmapCalls, 1);
        final paused = c.heatmapsPausedFor!;
        expect(paused, greaterThanOrEqualTo(const Duration(seconds: 30)));
        expect(paused, lessThanOrEqualTo(const Duration(seconds: 36)));

        // Batch, snapshot and recording are all refused locally.
        await expectLater(
          c.sendScreenHeatmapBatch([_view('a')]),
          throwsA(
            isA<IngestPausedException>().having(
              (e) => e.reason,
              'reason',
              'rate_limited',
            ),
          ),
        );
        await expectLater(
          c.uploadScreenHeatmapSnapshot({'screenViewId': 'a'}),
          throwsA(isA<IngestPausedException>()),
        );
        await expectLater(
          c.uploadScreenHeatmapRecording({'recordingId': 'r'}),
          throwsA(isA<IngestPausedException>()),
        );
        expect(transport.heatmapCalls, 1, reason: 'nothing sent while paused');

        now = now.add(const Duration(seconds: 37));
        expect(c.heatmapsPausedFor, isNull);
        await c.sendScreenHeatmapBatch([_view('a')]);
        await c.uploadScreenHeatmapSnapshot({'screenViewId': 'a'});
        expect(transport.heatmapCalls, 2);
        expect(transport.snapshotCalls, 1);

        // A rate limit keeps the data with the caller: no discard row.
        await c.flush();
        expect(transport.discardRows, isEmpty);
        await c.close();
      },
    );

    test('a 402 pauses until resetAt and counts heatmaps/quota', () async {
      final c = client();
      transport.heatmapFailures.add(
        _quota(resetAt: _t0.add(const Duration(minutes: 20))),
      );
      await expectLater(
        c.sendScreenHeatmapBatch([_view('a'), _view('b')]),
        throwsA(isA<TransportException>()),
      );
      expect(c.heatmapsPausedFor, const Duration(minutes: 20));
      await expectLater(
        c.uploadScreenHeatmapSnapshot({'screenViewId': 'a'}),
        throwsA(
          isA<IngestPausedException>().having(
            (e) => e.reason,
            'reason',
            'quota',
          ),
        ),
      );
      await c.flush();
      expect(transport.discardRows, [('heatmaps', 'quota', 2)]);

      now = now.add(const Duration(minutes: 20, seconds: 1));
      await c.sendScreenHeatmapBatch([_view('a')]);
      expect(transport.heatmapCalls, 2);
      await c.close();
    });

    test(
      'a 402 re-checks within an hour, or after 10 min without a reset',
      () async {
        final c = client();
        transport.recordingFailures.add(
          _quota(resetAt: _t0.add(const Duration(days: 12))),
        );
        await expectLater(
          c.uploadScreenHeatmapRecording({'recordingId': 'r'}),
          throwsA(isA<TransportException>()),
        );
        expect(c.heatmapsPausedFor, const Duration(hours: 1));

        now = now.add(const Duration(hours: 1, seconds: 1));
        transport.snapshotFailures.add(_quota());
        await expectLater(
          c.uploadScreenHeatmapSnapshot({'screenViewId': 'a'}),
          throwsA(isA<TransportException>()),
        );
        expect(c.heatmapsPausedFor, const Duration(minutes: 10));
        await c.close();
      },
    );

    test('heatmap backoff leaves events and spans alone', () async {
      final c = client();
      transport.heatmapFailures.add(_rateLimited(60));
      await expectLater(
        c.sendScreenHeatmapBatch([_view('a')]),
        throwsA(isA<TransportException>()),
      );
      await c.captureMessage('still sent');
      c.startTransaction('GET /x').finish();
      await c.flush();
      expect(transport.batches, hasLength(1));
      expect(transport.spanBatches, hasLength(1));
      await c.close();
    });
  });

  group('flags', () {
    Map<String, Object?> evaluation(String variation) => {
      'evaluations': [
        {
          'key': 'demo',
          'variationKey': variation,
          'valueJson': jsonEncode(variation == 'on'),
          'version': 1,
        },
      ],
    };

    test(
      'a 429 keeps the last evaluations and skips the network until it ends',
      () async {
        var reply = evaluation('on');
        final failures = <TransportException>[];
        transport.onEvaluateFlags = (_) async {
          if (failures.isNotEmpty) throw failures.removeAt(0);
          return reply;
        };
        final c = client(flags: true);
        await c.flags.reload();
        expect(c.flags.activeFlags['demo'], 'on');
        expect(transport.evaluateCalls, hasLength(1));

        failures.add(_rateLimited(120));
        reply = evaluation('off');
        await c.flags.reload();
        expect(transport.evaluateCalls, hasLength(2));
        expect(c.flags.activeFlags['demo'], 'on', reason: 'last good kept');
        final paused = c.flagsPausedFor!;
        expect(paused, greaterThanOrEqualTo(const Duration(seconds: 120)));

        await c.flags.reload();
        expect(transport.evaluateCalls, hasLength(2), reason: 'paused');

        now = now.add(const Duration(seconds: 145));
        await c.flags.reload();
        expect(transport.evaluateCalls, hasLength(3));
        expect(c.flags.activeFlags['demo'], 'off');

        // Flags aren't telemetry: nothing is reported as a discard.
        await c.flush();
        expect(transport.discardRows, isEmpty);
        await c.close();
      },
    );

    test('a 402 on flags pauses for 10 min without a reset time', () async {
      transport.onEvaluateFlags = (_) async => throw _quota();
      final c = client(flags: true);
      await c.flags.reload();
      expect(c.flagsPausedFor, const Duration(minutes: 10));
      await c.flags.reload();
      expect(transport.evaluateCalls, hasLength(1));
      await c.flush();
      expect(transport.discardRows, isEmpty);
      await c.close();
    });

    test('downloadDefinitions shares the flags pause', () async {
      transport.onEvaluateFlags = (_) async => throw _rateLimited(30);
      var downloads = 0;
      transport.onDownloadFlagDefinitions = (_) async {
        downloads++;
        return const {'items': <Object?>[]};
      };
      final c = client(flags: true);
      await c.flags.reload();
      await expectLater(
        c.flags.loadDefinitions(),
        throwsA(isA<IngestPausedException>()),
      );
      expect(downloads, 0);
      await c.close();
    });
  });

  test('a 402 naming the transactions meter pauses spans', () async {
    final c = client();
    transport.heatmapFailures.add(
      _quota(
        meter: 'transactions',
        resetAt: _t0.add(const Duration(minutes: 5)),
      ),
    );
    await expectLater(
      c.sendScreenHeatmapBatch([_view('a')]),
      throwsA(isA<TransportException>()),
    );
    c.startTransaction('GET /x').finish();
    await c.flush();
    expect(transport.spanBatches, isEmpty);
    expect(transport.discardRows, contains(('spans', 'quota', 1)));
    await c.close();
  });
}

class _UploadTransport extends FakeTransport {
  final heatmapFailures = <TransportException>[];
  final snapshotFailures = <TransportException>[];
  final recordingFailures = <TransportException>[];
  var heatmapCalls = 0;
  var snapshotCalls = 0;
  var recordingCalls = 0;
  final discardRows = <(String, String, int)>[];

  @override
  Future<Map<String, Object?>> sendScreenHeatmapBatch(
    List<Map<String, Object?>> screenViews,
  ) async {
    heatmapCalls++;
    if (heatmapFailures.isNotEmpty) throw heatmapFailures.removeAt(0);
    return const {'enabled': true};
  }

  @override
  Future<void> uploadScreenHeatmapSnapshot(Map<String, Object?> input) async {
    snapshotCalls++;
    if (snapshotFailures.isNotEmpty) throw snapshotFailures.removeAt(0);
  }

  @override
  Future<void> uploadScreenHeatmapRecording(Map<String, Object?> input) async {
    recordingCalls++;
    if (recordingFailures.isNotEmpty) throw recordingFailures.removeAt(0);
  }

  @override
  Future<void> reportDiscards(List<DiscardRow> discards) async {
    for (final row in discards) {
      discardRows.add((row.signal, row.reason, row.count));
    }
    await super.reportDiscards(discards);
  }
}
