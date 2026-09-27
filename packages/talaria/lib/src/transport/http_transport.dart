import 'dart:convert';

import 'package:http/http.dart' as http;

import '../analytics/analytics_event.dart';
import '../event.dart';
import '../sdk_info.dart';
import '../tracing/span.dart';
import 'discards.dart';
import 'ingest_error.dart';
import 'transport.dart';

String serverpodByteData(List<int> bytes) {
  final b64 = base64Encode(bytes);
  return "decode('$b64', 'base64')";
}

Map<String, Object?> unwrapServerpodResult(Map<String, Object?> raw) {
  final data = raw['data'];
  if (data is Map<String, Object?>) return data;
  if (data is Map) {
    return data.map((key, value) => MapEntry(key.toString(), value));
  }
  return raw;
}

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

  @override
  Future<Map<String, Object?>> sendScreenHeatmapBatch(
    List<Map<String, Object?>> screenViews,
  ) async {
    if (screenViews.isEmpty) return const {};
    final raw = await _postJson(
      path: '/screenHeatmaps/ingestBatch',
      payload: {
        'input': {
          '__className__': 'IngestScreenHeatmapBatchInput',
          'screenViews': screenViews,
        },
      },
      client: _http,
      label: 'screenHeatmaps/ingestBatch',
    );
    return unwrapServerpodResult(raw);
  }

  @override
  Future<void> uploadScreenHeatmapSnapshot(Map<String, Object?> input) async {
    await _postJson(
      path: '/screenHeatmaps/uploadSnapshot',
      payload: {
        'input': _encodeByteFields(input, const ['pngBytes']),
      },
      client: _http,
      label: 'screenHeatmaps/uploadSnapshot',
    );
  }

  @override
  Future<void> uploadScreenHeatmapRecording(Map<String, Object?> input) async {
    await _postJson(
      path: '/screenHeatmaps/uploadRecording',
      payload: {'input': _encodeRecording(input)},
      client: _http,
      label: 'screenHeatmaps/uploadRecording',
    );
  }

  Future<Map<String, Object?>> fetchSdkConfig({
    String? revision,
    String platform = 'dart',
    String sdkName = talariaSdkName,
    String sdkVersion = talariaSdkVersion,
  }) async {
    final response = await _postJson(
      path: '/sdk/getConfig',
      payload: {
        'input': {
          '__className__': 'GetSdkConfigInput',
          'schemaVersion': 1,
          'sdkName': sdkName,
          'sdkVersion': sdkVersion,
          'platform': platform,
          if (revision != null) 'revision': revision,
        },
      },
      client: _http,
      label: 'sdk/getConfig',
      timeout: const Duration(milliseconds: 200),
    );
    return response;
  }

  @override
  Future<void> reportDiscards(List<DiscardRow> discards) async {
    if (discards.isEmpty) {
      return;
    }
    await _postJson(
      path: '/sdk/reportDiscards',
      payload: {
        'input': {
          '__className__': 'ReportSdkDiscardsInput',
          'discards': [
            for (final row in discards)
              {
                '__className__': 'SdkDiscardCountInput',
                'signal': row.signal,
                'reason': row.reason,
                'count': row.count,
              },
          ],
        },
      },
      client: _http,
      label: 'sdk/reportDiscards',
    );
  }

  Future<Map<String, Object?>> _postJson({
    required String path,
    required Map<String, Object?> payload,
    required http.Client client,
    required String label,
    Duration? timeout,
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
          .timeout(timeout ?? this.timeout);
    } catch (e) {
      throw TransportException(
        'Talaria $label failed: $e',
        cause: e,
      );
    }

    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      if (response.body.isEmpty) return const {};
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, Object?>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
      return const {};
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

  static Map<String, Object?> _encodeByteFields(
    Map<String, Object?> input,
    List<String> fields,
  ) {
    final out = Map<String, Object?>.from(input);
    for (final field in fields) {
      final value = out[field];
      if (value is List<int>) out[field] = serverpodByteData(value);
    }
    final tiles = out['tiles'];
    if (tiles is List) {
      out['tiles'] = [
        for (final tile in tiles)
          if (tile is Map<String, Object?>)
            _encodeByteFields(tile, const ['pngBytes'])
          else
            tile,
      ];
    }
    return out;
  }

  static Map<String, Object?> _encodeRecording(Map<String, Object?> input) {
    final out = Map<String, Object?>.from(input);
    final frames = out['frames'];
    if (frames is List) {
      out['frames'] = [
        for (final frame in frames)
          if (frame is Map<String, Object?>)
            _encodeByteFields(frame, const ['pngBytes'])
          else
            frame,
      ];
    }
    return out;
  }
}
