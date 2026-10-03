import 'dart:io';

import 'package:talaria/src/transport/fake_transport.dart';
import 'package:talaria_serverpod/talaria_serverpod.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    await Talaria.reset();
  });

  test('HttpClient created after init continues the active trace', () async {
    final transport = FakeTransport();
    final options = TalariaOptions(
      dsn: 'https://api.example.com',
      apiKey: 'tal_live_test_key_for_unit_tests',
      defaultIntegrations: false,
      flushIntervalMs: 0,
    );
    options.enableTracing = true;
    options.tracesSampleRate = 1;
    await TalariaServerpod.init(options, transport: transport);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    String? traceparent;
    server.listen((request) {
      traceparent = request.headers.value(Traceparent.headerName);
      request.response.statusCode = 204;
      request.response.close();
    });

    final transaction = Talaria.getClient()!.startTransaction(
      'GET /checkout',
      kind: SpanKind.server,
    );
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/health'),
    );
    final response = await request.close();
    await response.drain<void>();
    transaction.finish();
    await Talaria.flush();

    expect(traceparent, isNotNull);
    expect(traceparent, contains(transaction.traceId));
    final spans = transport.spanBatches.expand((batch) => batch).toList();
    expect(
      spans.map((span) => span.name),
      contains('GET /health'),
    );
  });
}
