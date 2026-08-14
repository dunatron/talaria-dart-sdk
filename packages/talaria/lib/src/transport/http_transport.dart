import 'dart:convert';

import 'package:http/http.dart' as http;

import '../event.dart';
import '../tracing/span.dart';
import 'transport.dart';

/// Minimal Serverpod RPC client for `events/ingestBatch` and `spans/ingestBatch`.
///
/// [httpClient] is the ingest client — never wrap it with `TalariaHttpClient`.
/// Wrap application HTTP separately, or pass [spanHttpClient] for span ingest.
class HttpTransport implements Transport {
  HttpTransport({
    required this.baseUrl,
    required this.apiKey,
    this.timeout = const Duration(seconds: 3),
    http.Client? httpClient,
    http.Client? spanHttpClient,
  })  : _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _spanHttp = spanHttpClient;

  final String baseUrl;
  final String apiKey;
  final Duration timeout;
  final http.Client _http;
  final bool _ownsClient;
  final http.Client? _spanHttp;

  http.Client get _spansClient => _spanHttp ?? _http;

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

    await _postJson(
      path: '/events/ingestBatch',
      payload: payload,
      client: _http,
      label: 'events/ingestBatch',
    );
  }

  @override
  Future<void> sendSpanBatch(List<FinishedSpan> spans) async {
    if (spans.isEmpty) {
      return;
    }

    final payload = <String, Object?>{
      'input': {
        '__className__': 'IngestSpanBatchInput',
        'spans': [for (final s in spans) s.toWire()],
      },
    };

    await _postJson(
      path: '/spans/ingestBatch',
      payload: payload,
      client: _spansClient,
      label: 'spans/ingestBatch',
    );
  }

  Future<void> _postJson({
    required String path,
    required Map<String, Object?> payload,
    required http.Client client,
    required String label,
  }) async {
    final uri = Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');

    late final http.Response response;
    try {
      response = await client
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
        'Talaria $label failed: $e',
        cause: e,
      );
    }

    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      return;
    }

    throw TransportException(
      'Talaria $label failed: HTTP $status'
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
