import 'package:talaria/src/transport/event_queue.dart';
import 'package:talaria/src/transport/fake_transport.dart';
import 'package:talaria/talaria.dart';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

void main() {
  group('EventQueue', () {
    test('flushes when maxBatchSize reached', () async {
      final transport = FakeTransport();
      final queue = EventQueue(
        transport: transport,
        maxBatchSize: 2,
        flushIntervalMs: 0,
      );

      queue.enqueue(Event(
        message: 'one',
        environment: Environment.development,
        level: SeverityLevel.info,
      ));
      expect(transport.batches, isEmpty);

      queue.enqueue(Event(
        message: 'two',
        environment: Environment.development,
        level: SeverityLevel.info,
      ));

      await Future<void>.delayed(Duration.zero);
      await queue.flush();

      expect(transport.batches.length, 1);
      expect(transport.batches.first.length, 2);
    });
  });

  group('HttpTransport', () {
    test('posts Serverpod batch envelope', () async {
      Map<String, dynamic>? body;
      String? apiKey;
      final client = MockClient((request) async {
        apiKey = request.headers['X-API-Key'];
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{}', 200);
      });

      final transport = HttpTransport(
        baseUrl: 'https://api.example.com',
        apiKey: 'tal_live_testkey',
        httpClient: client,
      );

      await transport.sendBatch([
        Event(
          message: 'hello',
          environment: Environment.production,
          level: SeverityLevel.warning,
          platform: 'dart',
        ),
      ]);

      expect(apiKey, 'tal_live_testkey');
      expect(body!['input']['__className__'], 'IngestEventBatchInput');
      final events = body!['input']['events'] as List;
      expect(events.length, 1);
      expect(events.first['__className__'], 'IngestEventInput');
      expect(events.first['message'], 'hello');
      expect(events.first['environment'], 'production');
    });
  });
}
