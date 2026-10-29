import 'dart:io';

import 'package:serverpod/serverpod.dart';
import 'package:talaria/src/transport/fake_transport.dart';
// Only the public library: the middleware is exported from it.
import 'package:talaria_serverpod/talaria_serverpod.dart';
import 'package:test/test.dart';

/// Talaria SDK ingest and control calls are never traced. With a traced
/// Talaria server reporting to itself, tracing them looped: a rejected span
/// batch led to `sdk/reportDiscards`, which was traced, and so on.
const _sdkCalls = [
  'v1/events',
  'v1/spans',
  'v1/analytics',
  'v1/heatmaps',
  'v1/screenHeatmaps',
  'v1/replays',
  'v1/sdk',
  'v1/flags',
  'v1/monitors',
];

/// Dashboard methods on the same endpoints, and ordinary app endpoints, plus old paths.
const _traced = [
  'flags/list',
  'flags/create',
  'screenHeatmaps/listScreens',
  'screenHeatmaps/getRecording',
  'heatmaps/clickMap',
  'replays/start',
  'replays/get',
  'projects/list',
  // Old paths are no longer SDK paths (hard cut)
  'events/ingest',
  'events/ingestBatch',
  'spans/ingestBatch',
  'analytics/ingestBatch',
];

void main() {
  group('TalariaServerpodPaths', () {
    test('SDK calls (v1 paths) are noisy', () {
      for (final call in _sdkCalls) {
        expect(
          TalariaServerpodPaths.isNoisy(
            Uri.parse('http://localhost:8080/$call'),
          ),
          isTrue,
          reason: call,
        );
      }
    });

    test('dashboard, app calls, and old paths stay traced', () {
      for (final call in _traced) {
        expect(
          TalariaServerpodPaths.isNoisy(
            Uri.parse('http://localhost:8080/$call'),
          ),
          isFalse,
          reason: call,
        );
      }
      expect(
        TalariaServerpodPaths.isNoisy(Uri.parse('http://localhost:8080/sdk')),
        isFalse,
      );
    });
  });

  group('talariaRelicMiddleware', () {
    late FakeTransport transport;
    late TalariaClient client;
    late RelicServer server;
    late HttpClient http;

    setUp(() async {
      transport = FakeTransport();
      client = TalariaClient(
        TalariaOptions(
          url: 'https://api.example.com',
          apiKey: 'tal_prod_test_key_for_unit_tests',
          defaultIntegrations: false,
          flushIntervalMs: 0,
        )..applySdkDocument({
          'schemaVersion': 1,
          'active': true,
          'tracing': {'enabled': true, 'tracesSampleRate': 1.0},
        }),
        transport: transport,
      );
      final app = RelicApp()
        ..use(
          '/',
          talariaRelicMiddleware(
            client,
            skip: (url) => url.path.startsWith('/internal/'),
          ),
        )
        ..any('/**', (req) => Response.ok());
      server = await app.serve(address: InternetAddress.loopbackIPv4, port: 0);
      http = HttpClient();
    });

    tearDown(() async {
      http.close(force: true);
      await server.close(force: true);
      await client.close();
    });

    Future<int> post(String path) async {
      final req = await http.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}$path'),
      );
      final res = await req.close();
      await res.drain<void>();
      return res.statusCode;
    }

    test(
      'SDK calls (v1 paths) and skipped paths make no spans; others do',
      () async {
        for (final call in [..._sdkCalls, 'internal/jobs']) {
          expect(await post('/$call'), 200, reason: call);
        }
        await client.flush();
        expect(transport.spanBatches.expand((b) => b), isEmpty);

        expect(await post('/flags/list'), 200);
        await client.flush();
        expect(transport.spanBatches.expand((b) => b).map((s) => s.name), [
          'POST /flags/list',
        ]);
      },
    );
  });
}

/// Compile check: `attach` takes a skip predicate.
// ignore: unused_element
void _attachTakesSkip(Serverpod pod) =>
    TalariaServerpod.attach(pod, skip: (url) => url.path == '/internal');
