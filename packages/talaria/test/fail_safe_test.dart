import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:talaria/src/transport/fake_transport.dart';
import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

/// D19: a bad key or option only switches Talaria off. It never throws into
/// the host app, and transport faults never reach the caller.
void main() {
  final sk = TalariaCredential.mint(kind: 'sk');
  final wrongChecksum =
      '${sk.substring(0, sk.length - 1)}${sk.endsWith('0') ? '1' : '0'}';
  const oldLiveKey = 'tal_live_g2WhG4abcdefghijklmnopqrstuvwxyz0123456789';

  late List<String> warnings;

  setUp(() {
    FailSafe.reset();
    warnings = [];
    FailSafe.sink = warnings.add;
  });

  tearDown(() async {
    FailSafe.sink = null;
    RuntimeContext.clearCurrent();
    await Talaria.reset();
  });

  final badInits = <String, TalariaOptions Function()>{
    'no key': () => TalariaOptions(apiKey: ''),
    'an empty key': () => TalariaOptions(apiKey: '   '),
    'a malformed key': () => TalariaOptions(apiKey: oldLiveKey),
    'a wrong checksum': () => TalariaOptions(apiKey: wrongChecksum),
    'a monitor token': () =>
        TalariaOptions(apiKey: TalariaCredential.mint(kind: 'mon')),
    'a self cell without url': () =>
        TalariaOptions(apiKey: TalariaCredential.mint(cell: 'self')),
    'a bad option (NaN timeout)': () =>
        TalariaOptions(apiKey: sk, httpTimeoutSeconds: double.nan),
    'a bad option (NaN sampleRate)': () =>
        TalariaOptions(apiKey: sk, sampleRate: double.infinity),
  };

  Future<void> exerciseEveryApi(TalariaClient client) async {
    await client.captureException(StateError('boom'));
    await client.captureMessage('hello', level: SeverityLevel.error);
    await client.captureMessage('');
    await client.warn('w');
    await client.logger(tags: {'a': 'b'}).error('scoped');
    client.setUser('u1');
    client.setExtra({'k': 1});
    client.setTags({'t': 'v'});
    client.addBreadcrumb(Breadcrumb(type: 'default', message: 'crumb'));
    final span = client.startTransaction('t');
    span.finish();
    client.startSpan('s').finish();
    client.analytics.optIn();
    await client.analytics.track('signup', userId: 'u1');
    await client.analytics.identify('u1');
    expect(await client.flags.boolVariation('f', true), isTrue);
    await client.flush();
    await client.close();
  }

  group('a bad key or option disables Talaria', () {
    for (final entry in badInits.entries) {
      test('${entry.key}: no throw, no-op client, one warning, no network',
          () async {
        late TalariaOptions options;
        expect(() => options = entry.value(), returnsNormally);
        expect(options.enabled, isFalse);
        expect(options.disabledReason, isNotNull);
        expect(options.apiKey, isEmpty);

        final transport = FakeTransport();
        late TalariaClient client;
        expect(
          () => client = TalariaClient(options, transport: transport),
          returnsNormally,
        );
        expect(client.isEnabled, isFalse);
        expect(client.disabledReason, options.disabledReason);
        await exerciseEveryApi(client);

        expect(transport.batches, isEmpty);
        expect(transport.spanBatches, isEmpty);
        expect(transport.analyticsBatches, isEmpty);
        expect(warnings, hasLength(1), reason: warnings.join('\n'));
        expect(warnings.single, contains('Talaria is disabled'));
      });
    }

    test('shows at most the first 8 characters of the key', () {
      TalariaClient(TalariaOptions(apiKey: wrongChecksum));
      expect(warnings.single, contains('(${wrongChecksum.substring(0, 8)}…)'));
      expect(warnings.single, isNot(contains(wrongChecksum.substring(0, 9))));
    });

    test('warns once per process', () {
      TalariaClient(TalariaOptions(apiKey: oldLiveKey));
      TalariaClient(TalariaOptions(apiKey: ''));
      TalariaClient(TalariaOptions(apiKey: wrongChecksum));
      expect(warnings, hasLength(1));
    });

    test('copyWith keeps a disabled configuration disabled', () {
      final options = TalariaOptions(apiKey: oldLiveKey);
      final copy = options.copyWith(platform: 'flutter', tags: {'x': 'y'});
      expect(copy.enabled, isFalse);
      expect(copy.disabledReason, options.disabledReason);
      final forced = TalariaOptions(apiKey: sk, disabledReason: 'off');
      expect(forced.copyWith(platform: 'flutter').enabled, isFalse);
    });

    test('a disabled client installs no zone integration or timers', () async {
      final client = TalariaClient(
        TalariaOptions(apiKey: oldLiveKey, flushIntervalMs: 10),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(client.isEnabled, isFalse);
      await client.close();
    });

    test('a valid key still enables Talaria', () async {
      final transport = FakeTransport();
      final client = TalariaClient(
        TalariaOptions(apiKey: sk, defaultIntegrations: false),
        transport: transport,
      );
      expect(client.isEnabled, isTrue);
      expect(client.disabledReason, isNull);
      await client.captureException(StateError('sent'));
      await client.flush();
      expect(transport.batches, hasLength(1));
      expect(warnings.where((w) => w.contains('Talaria is disabled')), isEmpty);
      await client.close();
    });
  });

  group('the Talaria facade never throws', () {
    test('before init every call is a no-op', () async {
      expect(Talaria.isEnabled, isFalse);
      await Talaria.captureException(StateError('before init'));
      await Talaria.captureMessage('before init');
      await Talaria.warn('before init');
      Talaria.addBreadcrumb(Breadcrumb(type: 'default', message: 'x'));
      Talaria.setUser('u');
      Talaria.startTransaction('t').finish();
      expect(await Talaria.flags.boolVariation('f', false), isFalse);
      await Talaria.analytics.track('x', userId: 'u');
      expect(Talaria.anonymousId, isNotEmpty);
      await Talaria.flush();
      expect(warnings, isEmpty);
    });

    test('init with a bad key returns a disabled client', () async {
      final client = await Talaria.init(TalariaOptions(apiKey: oldLiveKey));
      expect(client.isEnabled, isFalse);
      expect(Talaria.isEnabled, isFalse);
      await Talaria.captureException(StateError('after bad init'));
      expect(warnings, hasLength(1));
    });

    test('a later valid init replaces a disabled client', () async {
      await Talaria.init(TalariaOptions(apiKey: oldLiveKey));
      final transport = FakeTransport();
      final client = await Talaria.init(
        TalariaOptions(apiKey: sk, defaultIntegrations: false),
        transport: transport,
      );
      expect(client.isEnabled, isTrue);
      await Talaria.captureMessage('now sent', level: SeverityLevel.error);
      await Talaria.flush();
      expect(transport.batches, hasLength(1));
    });
  });

  group('transport errors never reach the caller', () {
    final failures = <String, Future<http.Response> Function()>{
      '401': () async => http.Response(
            '{"className":"Unauthorized","retry":false}',
            401,
            headers: {'content-type': 'application/problem+json'},
          ),
      '500': () async => http.Response('oops', 500),
      'a timeout': () async {
        await Future<void>.delayed(const Duration(seconds: 2));
        return http.Response('{}', 200);
      },
      'a network error': () async =>
          throw http.ClientException('Connection refused'),
      'an unreadable body': () async => http.Response(
            'not json',
            200,
            headers: {'content-type': 'application/json'},
          ),
    };

    for (final entry in failures.entries) {
      test('${entry.key}: capture, flush and close complete normally',
          () async {
        var calls = 0;
        final http = MockClient((request) {
          calls++;
          return entry.value();
        });
        final options = TalariaOptions(
          apiKey: sk,
          url: 'http://127.0.0.1:9',
          defaultIntegrations: false,
          flushIntervalMs: 0,
          httpTimeoutSeconds: 0.5,
        );
        final client = TalariaClient(
          options,
          transport: HttpTransport(
            url: options.url,
            apiKey: options.apiKey,
            timeout: const Duration(milliseconds: 500),
            httpClient: http,
          ),
        );
        final uncaught = <Object>[];
        await runZonedGuarded(() async {
          for (var i = 0; i < 4; i++) {
            await client.captureException(StateError('boom $i'));
            await client.flush();
          }
          await client.close();
        }, (error, _) => uncaught.add(error));
        expect(uncaught, isEmpty);
        expect(calls, greaterThan(0));
        expect(
          warnings.where((w) => w.contains('Talaria is disabled')),
          isEmpty,
        );
        expect(
          warnings.where((w) => w.startsWith('[Talaria] ')).length,
          lessThanOrEqualTo(3),
          reason: warnings.join('\n'),
        );
      });
    }
  });

  group('FailSafe helpers', () {
    test('keyPreview shows at most 8 characters', () {
      expect(FailSafe.keyPreview('tal_pk_prod_nz1_secret'), 'tal_pk_p…');
      expect(FailSafe.keyPreview('short'), 'short');
      expect(FailSafe.keyPreview(null), '');
    });

    test('logRateLimited logs once per channel per interval', () {
      final t0 = DateTime(2026, 11, 3);
      expect(FailSafe.logRateLimited('a', 'first', now: t0), isTrue);
      expect(
        FailSafe.logRateLimited(
          'a',
          'again',
          now: t0.add(const Duration(seconds: 1)),
        ),
        isFalse,
      );
      expect(FailSafe.logRateLimited('b', 'other', now: t0), isTrue);
      expect(
        FailSafe.logRateLimited(
          'a',
          'later',
          now: t0.add(FailSafe.transportLogInterval),
        ),
        isTrue,
      );
      expect(warnings, ['first', 'other', 'later']);
    });

    test('a throwing sink never reaches the caller', () {
      FailSafe.sink = (_) => throw StateError('logger gone');
      expect(() => FailSafe.warnDisabledOnce('x'), returnsNormally);
      expect(() => FailSafe.logRateLimited('c', 'y'), returnsNormally);
    });
  });
}
