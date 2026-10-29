import 'dart:convert';
import 'dart:io' show gzip;

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

/// Gzip request bodies: only after getConfig advertises
/// `capabilities.gzipRequests`, never on the shutdown flush, and a server
/// that answers 415 gets the body again uncompressed.
void main() {
  List<Event> bigBatch() => [
        for (var i = 0; i < 40; i++)
          Event(
            message: 'TypeError: checkout failed for cart $i',
            level: SeverityLevel.error,
          ),
      ];

  ({HttpTransport transport, List<http.Request> seen}) setup({
    int Function(http.Request)? status,
  }) {
    final seen = <http.Request>[];
    final client = MockClient((request) async {
      seen.add(request);
      return http.Response('{}', status?.call(request) ?? 200);
    });
    return (
      transport: HttpTransport(
        url: 'https://api.example.com',
        apiKey: 'tal_test_testkey',
        httpClient: client,
      ),
      seen: seen,
    );
  }

  Map<String, Object?> decode(http.Request r) {
    final gzipped = r.headers['Content-Encoding'] == 'gzip';
    final bytes = gzipped ? gzip.decode(r.bodyBytes) : r.bodyBytes;
    return jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
  }

  test('off by default: an older server never sees Content-Encoding', () async {
    final (:transport, :seen) = setup();
    await transport.sendBatch(bigBatch());
    expect(seen.single.headers['Content-Encoding'], isNull);
    expect(transport.gzipRequests, isFalse);
  });

  test(
    'advertised: large bodies are gzipped and decode to the same JSON',
    () async {
      final (:transport, :seen) = setup();
      final plain = setup();
      transport.applyCapabilities({'gzipRequests': true});
      await transport.sendBatch(bigBatch());
      await plain.transport.sendBatch(bigBatch());
      final zipped = seen.single;
      expect(zipped.headers['Content-Encoding'], 'gzip');
      expect(zipped.headers['Content-Type'], startsWith('application/json'));
      expect(
        zipped.bodyBytes.length,
        lessThan(plain.seen.single.bodyBytes.length ~/ 2),
      );
      final a = decode(zipped)['input'] as Map;
      final b = decode(plain.seen.single)['input'] as Map;
      expect(
        (a['events'] as List).map((e) => (e as Map)['message']),
        (b['events'] as List).map((e) => (e as Map)['message']),
      );
    },
  );

  test('small bodies stay plain even when advertised', () async {
    final (:transport, :seen) = setup();
    transport.applyCapabilities({'gzipRequests': true});
    await transport.sendBatch([Event(message: 'x', level: SeverityLevel.info)]);
    expect(seen.single.headers['Content-Encoding'], isNull);
  });

  test('capabilities missing or false switch gzip off again', () {
    final (:transport, seen: _) = setup();
    transport.applyCapabilities({'gzipRequests': true});
    expect(transport.gzipRequests, isTrue);
    transport.applyCapabilities(null);
    expect(transport.gzipRequests, isFalse);
    transport.applyCapabilities({'gzipRequests': true});
    transport.applyCapabilities({'gzipRequests': false});
    expect(transport.gzipRequests, isFalse);
    transport.applyCapabilities({'binaryUploads': true});
    expect(transport.gzipRequests, isFalse);
  });

  test('the shutdown flush is never gzipped', () async {
    final (:transport, :seen) = setup();
    transport.applyCapabilities({'gzipRequests': true});
    transport.beginFinalFlush();
    await transport.sendBatch(bigBatch());
    expect(seen.single.headers['Content-Encoding'], isNull);
  });

  test(
    'a 415 for a gzipped body resends it plain and stops compressing',
    () async {
      final (:transport, :seen) = setup(
        status: (r) => r.headers['Content-Encoding'] == 'gzip' ? 415 : 200,
      );
      transport.applyCapabilities({'gzipRequests': true});
      await transport.sendBatch(bigBatch());
      expect(seen.map((r) => r.headers['Content-Encoding']), ['gzip', null]);
      expect(decode(seen[0]), decode(seen[1]));
      expect(transport.gzipRequests, isFalse);
      await transport.sendBatch(bigBatch());
      expect(seen.last.headers['Content-Encoding'], isNull);
    },
  );

  test('TalariaClient: gzip follows getConfig, close() sends plain', () async {
    TalariaClient.clearPolicyCache();
    final seen = <http.Request>[];
    var advertise = true;
    final httpClient = MockClient((request) async {
      seen.add(request);
      if (request.url.path == '/sdk/getConfig') {
        return http.Response(
          jsonEncode({
            'schemaVersion': 1,
            'revision': 'r1',
            'active': true,
            'ttlSeconds': 300,
            if (advertise) 'capabilities': {'gzipRequests': true},
          }),
          200,
        );
      }
      return http.Response('{}', 200);
    });
    final transport = HttpTransport(
      url: 'https://api.example.com',
      apiKey: 'tal_prod_gzip_client_test',
      httpClient: httpClient,
    );
    final client = TalariaClient(
      TalariaOptions(
        url: 'https://api.example.com',
        apiKey: 'tal_prod_gzip_client_test',
        defaultIntegrations: false,
        flushIntervalMs: 0,
      ),
      transport: transport,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(transport.gzipRequests, isTrue);

    for (var i = 0; i < 40; i++) {
      client.captureMessage(
        'TypeError: checkout failed for cart $i',
        level: SeverityLevel.error,
      );
    }
    await client.flush();
    final batch = seen.lastWhere((r) => r.url.path == '/v1/events');
    expect(batch.headers['Content-Encoding'], 'gzip');

    for (var i = 0; i < 40; i++) {
      client.captureMessage(
        'TypeError: checkout failed for cart $i',
        level: SeverityLevel.error,
      );
    }
    await client.close();
    final last = seen.lastWhere((r) => r.url.path == '/v1/events');
    expect(identical(last, batch), isFalse);
    expect(last.headers['Content-Encoding'], isNull);
    advertise = false;
    TalariaClient.clearPolicyCache();
  });
}
