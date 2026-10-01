import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:talaria/src/transport/fake_transport.dart';
import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    RuntimeContext.clearCurrent();
    await Talaria.reset();
  });

  TalariaOptions options({
    bool enableFlags = false,
    bool enableAnalytics = false,
    TalariaStorage? storage,
  }) {
    final created = TalariaOptions(
      dsn: 'https://api.example.com',
      apiKey: 'tal_live_test_key_for_unit_tests',
      platform: 'dart',
      storage: storage,
      defaultIntegrations: false,
      flushIntervalMs: 0,
      httpTimeoutSeconds: 1,
    );
    created.applySdkDocument({
      'schemaVersion': 1,
      'active': true,
      'flags': {'enabled': enableFlags},
      'analytics': {'enabled': enableAnalytics},
    });
    return created;
  }

  Map<String, Object?> evaluateResponse({
    required String key,
    required String variationKey,
    required Object? value,
    int version = 1,
    String? reason,
  }) {
    return {
      'evaluations': [
        {
          'key': key,
          'variationKey': variationKey,
          'valueJson': jsonEncode(value),
          'version': version,
          if (reason != null) 'reason': reason,
        },
      ],
    };
  }

  test('policy-gated: defaults without network when flags disabled', () async {
    final transport = FakeTransport();
    transport.onEvaluateFlags = (_) async =>
        evaluateResponse(key: 'demo', variationKey: 'on', value: true);

    final client = TalariaClient(options(enableFlags: false), transport: transport);

    expect(await client.flags.boolVariation('demo', false), isFalse);
    expect(transport.evaluateCalls, isEmpty);
    await client.close();
  });

  test('boolVariation uses evaluate result and stamps event tags', () async {
    final transport = FakeTransport();
    transport.onEvaluateFlags = (_) async => evaluateResponse(
          key: 'demo-kill-switch',
          variationKey: 'on',
          value: true,
        );

    final client = TalariaClient(options(enableFlags: true), transport: transport);
    await client.flags.reload();

    expect(await client.flags.boolVariation('demo-kill-switch', false), isTrue);
    expect(client.flags.activeFlags['demo-kill-switch'], 'on');
    expect(client.flags.stampTags()['flag.demo-kill-switch'], 'on');

    await client.captureMessage('with flags');
    await client.flush();

    final tags = transport.batches.single.single.tags!;
    expect(tags['flag.demo-kill-switch'], 'on');
    await client.close();
  });

  test('string and json variations decode valueJson', () async {
    final transport = FakeTransport();
    transport.onEvaluateFlags = (_) async => {
          'evaluations': [
            {
              'key': 'copy',
              'variationKey': 'b',
              'valueJson': jsonEncode('welcome'),
              'version': 2,
            },
            {
              'key': 'remote',
              'variationKey': 'cfg',
              'valueJson': jsonEncode({'theme': 'dark'}),
              'version': 3,
            },
          ],
        };

    final client = TalariaClient(options(enableFlags: true), transport: transport);
    await client.flags.reload();

    expect(await client.flags.stringVariation('copy', 'control'), 'welcome');
    final json = await client.flags.jsonVariation('remote', {'theme': 'light'});
    expect(json, {'theme': 'dark'});
    expect(await client.flags.stringVariation('missing', 'fallback'), 'fallback');
    await client.close();
  });

  test('disk cache serves last evaluation for matching context', () async {
    final storage = MemoryTalariaStorage();
    final transport = FakeTransport();
    var calls = 0;
    transport.onEvaluateFlags = (_) async {
      calls++;
      return evaluateResponse(key: 'demo', variationKey: 'on', value: true);
    };

    final client1 = TalariaClient(
      options(enableFlags: true, storage: storage),
      transport: transport,
      storage: storage,
    );
    await client1.flags.reload();
    expect(await client1.flags.boolVariation('demo', false), isTrue);
    expect(calls, 1);
    await client1.close();

    final transport2 = FakeTransport();
    // Hang evaluate so we exercise the disk cache path, not a network overwrite.
    transport2.onEvaluateFlags = (_) => Completer<Map<String, Object?>>().future;
    final client2 = TalariaClient(
      options(enableFlags: true, storage: storage),
      transport: transport2,
      storage: storage,
    );
    // Cache hit without waiting on network.
    expect(await client2.flags.boolVariation('demo', false), isTrue);
    await client2.close();
  });

  test('setUser reloads evaluate with userId', () async {
    final transport = FakeTransport();
    transport.onEvaluateFlags = (input) async {
      return evaluateResponse(
        key: 'plan-gate',
        variationKey: input['userId'] == 'user_9' ? 'on' : 'off',
        value: input['userId'] == 'user_9',
      );
    };

    final client = TalariaClient(options(enableFlags: true), transport: transport);
    await client.flags.reload();
    expect(await client.flags.boolVariation('plan-gate', false), isFalse);

    client.setUser('user_9');
    await Future<void>.delayed(Duration.zero);
    await client.flags.reload();
    expect(await client.flags.boolVariation('plan-gate', false), isTrue);
    expect(
      transport.evaluateCalls.any((c) => c['userId'] == 'user_9'),
      isTrue,
    );
    await client.close();
  });

  test('start timeout returns default when evaluate is slow', () async {
    final transport = FakeTransport();
    transport.onEvaluateFlags = (_) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return evaluateResponse(key: 'slow', variationKey: 'on', value: true);
    };

    final client = TalariaClient(options(enableFlags: true), transport: transport);
    client.flags.startTimeout = const Duration(milliseconds: 20);

    final value = await client.flags.boolVariation('slow', false);
    expect(value, isFalse);
    await client.close();
  });

  test('active=false disables flags in applySdkDocument', () {
    final opts = TalariaOptions(
      dsn: 'https://api.example.com',
      apiKey: 'tal_live_test_key_for_unit_tests',
      defaultIntegrations: false,
    );
    opts.applySdkDocument({
      'schemaVersion': 1,
      'active': true,
      'flags': {'enabled': true},
    });
    expect(opts.enableFlags, isTrue);
    opts.applySdkDocument({
      'schemaVersion': 1,
      'active': false,
    });
    expect(opts.enableFlags, isFalse);
  });

  test('copyWith preserves enableFlags', () {
    final opts = TalariaOptions(
      dsn: 'https://api.example.com',
      apiKey: 'tal_live_test_key_for_unit_tests',
      defaultIntegrations: false,
    )..enableFlags = true;
    final copied = opts.copyWith(platform: 'flutter');
    expect(copied.enableFlags, isTrue);
    expect(copied.platform, 'flutter');
  });

  test('HttpTransport posts EvaluateFlagsInput envelope', () async {
    Map<String, dynamic>? body;
    String? path;
    final httpClient = MockClient((request) async {
      path = request.url.path;
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'data': {
            'evaluations': [
              {
                'key': 'demo',
                'variationKey': 'on',
                'valueJson': 'true',
                'version': 1,
              },
            ],
          },
        }),
        200,
      );
    });

    final transport = HttpTransport(
      baseUrl: 'https://api.example.com',
      apiKey: 'tal_live_testkey',
      httpClient: httpClient,
    );

    final result = await transport.evaluateFlags({
      'anonymousId': 'anon_1',
      'userId': 'user_1',
      'attributes': {'plan': 'team'},
    });

    expect(path, '/flags/evaluate');
    expect(body!['input']['__className__'], 'EvaluateFlagsInput');
    expect(body!['input']['anonymousId'], 'anon_1');
    expect(body!['input']['attributes']['plan'], 'team');
    expect((result['evaluations'] as List).single['key'], 'demo');
  });

  test('optional \$feature_flag_called once per key per session', () async {
    final transport = FakeTransport();
    transport.onEvaluateFlags = (_) async => evaluateResponse(
          key: 'demo',
          variationKey: 'on',
          value: true,
        );

    final client = TalariaClient(
      options(enableFlags: true, enableAnalytics: true),
      transport: transport,
    );
    await client.flags.reload();
    await client.flags.boolVariation('demo', false);
    await client.flags.boolVariation('demo', false);
    await client.flush();

    final names = transport.analyticsBatches
        .expand((b) => b)
        .map((e) => e.name)
        .toList();
    expect(names.where((n) => n == r'$feature_flag_called'), hasLength(1));
    await client.close();
  });
}
