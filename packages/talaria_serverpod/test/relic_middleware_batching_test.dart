import 'dart:io';

import 'package:serverpod/serverpod.dart';
import 'package:talaria/src/transport/fake_transport.dart';
import 'package:talaria/talaria.dart';
import 'package:talaria_serverpod/src/relic_middleware.dart';
import 'package:test/test.dart';

/// The middleware used to `await client.flush()` after every traced request:
/// one `/v1/spans` request per request, so the default 100/min per-key limit
/// was hit at about 100 traced requests a minute. Spans now wait for the
/// client's batch.
void main() {
  late FakeTransport transport;
  late TalariaClient client;
  late RelicServer server;
  late HttpClient http;

  setUp(() async {
    transport = FakeTransport();
    client = TalariaClient(
      TalariaOptions(
        url: 'https://api.example.com',
        apiKey:
            'tal_sk_test_nz1_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg3B299S',
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
      ..use('/', talariaRelicMiddleware(client))
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

  test('traced requests do not each trigger a span export', () async {
    for (var i = 0; i < 20; i++) {
      expect(await post('/projects/list'), 200);
    }
    expect(transport.spanBatches, isEmpty, reason: 'no per-request flush');

    await client.flush();
    expect(transport.spanBatches, hasLength(1));
    expect(transport.spanBatches.single, hasLength(20));
    expect(transport.spanBatches.single.map((s) => s.name).toSet(), {
      'POST /projects/list',
    });
  });
}
