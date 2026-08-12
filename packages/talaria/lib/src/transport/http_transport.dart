import 'dart:convert';

import 'package:http/http.dart' as http;

import '../event.dart';
import 'transport.dart';

/// Minimal Serverpod RPC client for `events/ingestBatch`.
class HttpTransport implements Transport {
  HttpTransport({
    required this.baseUrl,
    required this.apiKey,
    this.timeout = const Duration(seconds: 3),
    http.Client? httpClient,
  })  : _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  final String baseUrl;
  final String apiKey;
  final Duration timeout;
  final http.Client _http;
  final bool _ownsClient;

  @override
  Future<void> sendBatch(List<Event> events) async {
    if (events.isEmpty) {
      return;
    }

    final payload = <String, Object?>{
      'input': {
        '__className__': 'IngestEventBatchInput',
        'events': [for (final e in events) e.toWire()],
      },
    };

    final uri = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/events/ingestBatch');

    late final http.Response response;
    try {
      response = await _http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'X-API-Key': apiKey,
            },
            body: jsonEncode(payload),
          )
          .timeout(timeout);
    } catch (e) {
      throw TransportException(
        'Talaria events/ingestBatch failed: $e',
        cause: e,
      );
    }

    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      return;
    }

    throw TransportException(
      'Talaria events/ingestBatch failed: HTTP $status'
      '${_formatErrorDetail(response.body).isEmpty ? '' : ' — ${_formatErrorDetail(response.body)}'}',
      statusCode: status,
    );
  }

  void close() {
    if (_ownsClient) {
      _http.close();
    }
  }

  static String _formatErrorDetail(String body) {
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map) {
        final className = parsed['className'] ?? parsed['exception'];
        final message = parsed['message'];
        final parts = <String>[
          if (className is String) className,
          if (message is String) message,
        ];
        if (parts.isNotEmpty) {
          return parts.join(': ');
        }
      }
    } catch (_) {}
    if (body.length <= 400) {
      return body;
    }
    return body.substring(0, 400);
  }
}
