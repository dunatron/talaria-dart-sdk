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

      queue.enqueue(Event(message: 'one', level: SeverityLevel.info));
      expect(transport.batches, isEmpty);

      queue.enqueue(Event(message: 'two', level: SeverityLevel.info));

      await Future<void>.delayed(Duration.zero);
      await queue.flush();

      expect(transport.batches.length, 1);
      expect(transport.batches.first.length, 2);
    });
  });

  group('HttpTransport', () {
    test('posts a plain JSON batch with bearer auth', () async {
      Map<String, dynamic>? body;
      String? auth;
      final client = MockClient((request) async {
        auth = request.headers['Authorization'];
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{}', 200);
      });

      final transport = HttpTransport(
        url: 'https://api.example.com',
        apiKey:
            'tal_sk_test_nz1_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg3B299S',
        httpClient: client,
      );

      await transport.sendBatch([
        Event(message: 'hello', level: SeverityLevel.warning, platform: 'dart'),
      ]);

      expect(
        auth,
        'Bearer tal_sk_test_nz1_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg3B299S',
      );
      expect(body!.containsKey('input'), isFalse);
      final events = body!['events'] as List;
      expect(events.length, 1);
      expect(events.first['message'], 'hello');
    });

    test('reads problem+json invalid_key', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'type': 'https://newtalaria.com/docs/reference/errors#invalid_key',
            'title': 'Invalid API key',
            'status': 401,
            'detail': 'Invalid API key',
            'code': 'invalid_key',
            'requestId': 'req_123',
          }),
          401,
          headers: {'content-type': 'application/problem+json'},
        );
      });

      final transport = HttpTransport(
        url: 'https://api.example.com',
        apiKey:
            'tal_sk_test_nz1_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg3B299S',
        httpClient: client,
      );

      try {
        await transport.sendBatch([
          Event(message: 'hello', level: SeverityLevel.error),
        ]);
        fail('expected TransportException');
      } on TransportException catch (e) {
        expect(e.code, 'invalid_key');
        expect(e.retry, isFalse);
        expect(e.bodyMessage, 'Invalid API key');
        expect(e.requestId, 'req_123');
        expect(e.statusCode, 401);
      }
    });
  });
}
