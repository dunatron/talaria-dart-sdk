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
  'events/ingest',
  'events/ingestBatch',
  'spans/ingestBatch',
  'analytics/ingestBatch',
  'heatmaps/ingestBatch',
  'heatmaps/uploadSnapshot',
  'screenHeatmaps/ingestBatch',
  'screenHeatmaps/uploadSnapshot',
  'screenHeatmaps/uploadRecording',
  'replays/ingestSegment',
  'replays/ingestSegmentBatch',
  'sdk/getConfig',
  'sdk/reportDiscards',
  'flags/evaluate',
  'flags/downloadDefinitions',
];

/// Dashboard methods on the same endpoints, and ordinary app endpoints.
const _traced = [
  'flags/list',
  'flags/create',
  'screenHeatmaps/listScreens',
  'screenHeatmaps/getRecording',
  'heatmaps/clickMap',
  'replays/start',
  'replays/get',
  'projects/list',
];

void main() {
  group('TalariaServerpodPaths', () {
    test('SDK calls are noisy as /endpoint/method and ?method=', () {
      for (final call in _sdkCalls) {
        final [endpoint, method] = call.split('/');
        expect(
          TalariaServerpodPaths.isNoisy(
            Uri.parse('http://localhost:8080/$call'),
          ),
          isTrue,
          reason: call,
        );
        expect(
          TalariaServerpodPaths.isNoisy(
            Uri.parse('http://localhost:8080/$endpoint?method=$method'),
          ),
          isTrue,
          reason: '$call as ?method=',
        );
        expect(
          TalariaServerpodPaths.shouldSkipSession(
            endpoint: endpoint,
            method: method,
          ),
          isTrue,
          reason: '$call session',
        );
      }
    });

    test('dashboard and app calls on the same endpoints stay traced', () {
      for (final call in _traced) {
        final [endpoint, method] = call.split('/');
        expect(
          TalariaServerpodPaths.isNoisy(
            Uri.parse('http://localhost:8080/$call'),
          ),
          isFalse,
          reason: call,
        );
        expect(
          TalariaServerpodPaths.shouldSkipSession(
            endpoint: endpoint,
            method: method,
          ),
          isFalse,
          reason: '$call session',
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

    test('SDK calls and skipped paths make no spans; others do', () async {
      for (final call in [..._sdkCalls, 'internal/jobs']) {
        expect(await post('/$call'), 200, reason: call);
      }
      await client.flush();
      expect(transport.spanBatches.expand((b) => b), isEmpty);

      expect(await post('/flags/list'), 200);
      await client.flush();
      expect(
        transport.spanBatches.expand((b) => b).map((s) => s.name),
        ['POST /flags/list'],
      );
    });
  });
}

/// Compile check: `attach` takes a skip predicate.
// ignore: unused_element
void _attachTakesSkip(Serverpod pod) =>
    TalariaServerpod.attach(pod, skip: (url) => url.path == '/internal');
