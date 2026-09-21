import 'dart:convert';

import 'package:http/http.dart' as http;

import '../analytics/analytics_event.dart';
import '../event.dart';
import '../tracing/span.dart';
import 'ingest_error.dart';
import 'transport.dart';

/// Minimal Serverpod RPC client for ingestBatch endpoints.
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

  @override
  Future<void> sendAnalyticsBatch(List<AnalyticsEvent> events) async {
    if (events.isEmpty) {
      return;
    }

    final payload = <String, Object?>{
      'input': {
        '__className__': 'IngestAnalyticsEventBatchInput',
        'events': [for (final e in events) e.toWire()],
      },
    };

    await _postJson(
      path: '/analytics/ingestBatch',
      payload: payload,
      client: _http,
      label: 'analytics/ingestBatch',
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

    final parsed = IngestError.parse(response.body);
    final detail = _formatErrorDetail(response.body, parsed);
    throw TransportException(
      'Talaria $label failed: HTTP $status${detail.isEmpty ? '' : ' — $detail'}',
      statusCode: status,
      className: parsed.className,
      retry: parsed.retry,
      bodyMessage: parsed.message,
    );
  }

  void close() {
    if (_ownsClient) {
      _http.close();
    }
  }

  static String _formatErrorDetail(String body, IngestError parsed) {
    final parts = <String>[
      if (parsed.className != null) parsed.className!,
      if (parsed.message != null) parsed.message!,
    ];
    if (parts.isNotEmpty) {
      return parts.join(': ');
    }
    if (body.length <= 400) {
      return body;
    }
    return body.substring(0, 400);
  }
}
