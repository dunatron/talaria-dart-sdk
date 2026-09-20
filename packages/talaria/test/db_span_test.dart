import 'package:talaria/src/transport/fake_transport.dart';
import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    await Talaria.reset();
  });

  test('records a client db span and breadcrumb', () async {
    final transport = FakeTransport();
    final client = TalariaClient(
      TalariaOptions(
        dsn: 'https://api.example.com',
        apiKey: 'tal_live_test_key_for_unit_tests',
        environment: 'development',
        tracesSampleRate: 1.0,
        defaultIntegrations: false,
        flushIntervalMs: 0,
      ),
      transport: transport,
    );

    final root = client.startTransaction('POST /items');
    final result = await DbSpan.trace(
      client,
      system: 'postgresql',
      sql: 'SELECT * FROM items WHERE id = 3',
      run: () async => 42,
    );
    expect(result, 42);
    root.finish();
    await client.flush();

    final db = transport.spanBatches.expand((b) => b).firstWhere(
          (s) => s.name == 'SELECT items',
        );
    expect(db.kind, SpanKind.client);
    expect(db.attributes['db.system.name'], 'postgresql');
    expect(db.attributes['db.query.text'], 'SELECT * FROM items WHERE id = ?');
    await client.close();
  });
}
