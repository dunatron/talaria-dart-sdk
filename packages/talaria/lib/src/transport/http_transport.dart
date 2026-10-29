import 'dart:convert';

import 'package:http/http.dart' as http;

import '../analytics/analytics_event.dart';
import '../event.dart';
import '../sdk_info.dart';
import '../tracing/span.dart';
import 'discards.dart';
import 'gzip_stub.dart' if (dart.library.io) 'gzip_io.dart';
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

/// Minimal HTTP client for `/v1/...` batch endpoints.
///
/// [httpClient] is the ingest client — never wrap it with `TalariaHttpClient`.
/// Wrap application HTTP separately, or pass [spanHttpClient] for span ingest.
class HttpTransport implements Transport {
  HttpTransport({
    required this.url,
    required this.apiKey,
    this.timeout = const Duration(seconds: 3),
    http.Client? httpClient,
    http.Client? spanHttpClient,
  })  : _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _spanHttp = spanHttpClient;

  final String url;
  final String apiKey;
  final Duration timeout;
  final http.Client _http;
  final bool _ownsClient;
  final http.Client? _spanHttp;

  http.Client get _spansClient => _spanHttp ?? _http;

  /// Smallest JSON body worth compressing. Below this, gzip's header and
  /// CPU cost more than they save.
  static const gzipMinBytes = 1024;

  /// Set from `sdk.getConfig` `capabilities.gzipRequests`. Off until the
  /// server says it accepts `Content-Encoding: gzip`, so older servers never
  /// see a compressed body.
  bool get gzipRequests => _gzipRequests;
  bool _gzipRequests = false;

  /// True once [beginFinalFlush] ran: the last sends before shutdown go
  /// uncompressed (no CPU spent while the process or page is going away).
  bool get finalFlush => _finalFlush;
  bool _finalFlush = false;

  /// Reads the `capabilities` object of a getConfig response (full or
  /// `unchanged`). A missing object means an older server: no gzip.
  ///
  /// `capabilities.binaryUploads` (raw gzip replay segments and heatmap
  /// snapshots) is not used here: this SDK sends neither web replays nor web
  /// heatmap snapshots.
  void applyCapabilities(Object? capabilities) {
    _gzipRequests = capabilities is Map && capabilities['gzipRequests'] == true;
  }

  /// Called by `TalariaClient.close` before its last flush.
  void beginFinalFlush() => _finalFlush = true;

  /// The body to send and whether it is gzipped.
  (List<int>, bool) encodeBody(String json) {
    final bytes = utf8.encode(json);
    if (!_gzipRequests || _finalFlush || bytes.length < gzipMinBytes) {
      return (bytes, false);
    }
    final gz = gzipEncodeOrNull(bytes);
    if (gz == null || gz.length >= bytes.length) return (bytes, false);
    return (gz, true);
  }

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
      path: '/v1/events',
      payload: payload,
      client: _http,
      label: 'v1/events',
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
      path: '/v1/spans',
      payload: payload,
      client: _spansClient,
      label: 'v1/spans',
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
      path: '/v1/analytics',
      payload: payload,
      client: _http,
      label: 'v1/analytics',
    );
  }

  @override
  Future<Map<String, Object?>> sendScreenHeatmapBatch(
    List<Map<String, Object?>> screenViews,
  ) async {
    if (screenViews.isEmpty) return const {};
    final raw = await _postJson(
      path: '/v1/screenHeatmaps',
      payload: {
        'input': {
          '__className__': 'IngestScreenHeatmapBatchInput',
          'screenViews': screenViews,
        },
      },
      client: _http,
      label: 'v1/screenHeatmaps',
    );
    return unwrapServerpodResult(raw);
  }

  @override
  Future<void> uploadScreenHeatmapSnapshot(Map<String, Object?> input) async {
    await _postJson(
      path: '/v1/screenHeatmaps/uploadSnapshot',
      payload: {
        'input': _encodeByteFields(input, const ['pngBytes']),
      },
      client: _http,
      label: 'v1/screenHeatmaps/uploadSnapshot',
      timeout: const Duration(seconds: 20),
    );
  }

  @override
  Future<void> uploadScreenHeatmapRecording(Map<String, Object?> input) async {
    await _postJson(
      path: '/v1/screenHeatmaps/uploadRecording',
      payload: {'input': _encodeRecording(input)},
      client: _http,
      label: 'v1/screenHeatmaps/uploadRecording',
      timeout: const Duration(seconds: 20),
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
      timeout: const Duration(seconds: 5),
    );
    return response;
  }

  @override
  Future<Map<String, Object?>> evaluateFlags(Map<String, Object?> input) async {
    final body = <String, Object?>{
      '__className__': 'EvaluateFlagsInput',
      ...input,
    };
    final raw = await _postJson(
      path: '/flags/evaluate',
      payload: {'input': body},
      client: _http,
      label: 'flags/evaluate',
    );
    return unwrapServerpodResult(raw);
  }

  @override
  Future<Map<String, Object?>> downloadFlagDefinitions(
    Map<String, Object?> input,
  ) async {
    final body = <String, Object?>{
      '__className__': 'DownloadFlagDefinitionsInput',
      ...input,
    };
    final raw = await _postJson(
      path: '/flags/downloadDefinitions',
      payload: {'input': body},
      client: _http,
      label: 'flags/downloadDefinitions',
    );
    return unwrapServerpodResult(raw);
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
    final uri = Uri.parse('${url.replaceAll(RegExp(r'/+$'), '')}$path');

    final (body, gzipped) = encodeBody(jsonEncode(payload));
    late http.Response response;
    try {
      response = await _send(
        client,
        uri,
        body,
        gzipped: gzipped,
        timeout: timeout,
      );
      if (gzipped && response.statusCode == 415) {
        // The server stopped accepting gzip (rollback): stop compressing
        // and resend this body plain, once.
        _gzipRequests = false;
        response = await _send(
          client,
          uri,
          utf8.encode(jsonEncode(payload)),
          gzipped: false,
          timeout: timeout,
        );
      }
    } catch (e) {
      throw TransportException('Talaria $label failed: $e', cause: e);
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
      retryAfter: retryAfterOf(response.headers['retry-after']) ??
          (parsed.retryAfterSeconds == null
              ? null
              : Duration(seconds: parsed.retryAfterSeconds!)),
      resetAt: parsed.resetAt,
      meter: parsed.meter,
    );
  }

  Future<http.Response> _send(
    http.Client client,
    Uri uri,
    List<int> body, {
    required bool gzipped,
    Duration? timeout,
  }) {
    return client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'X-API-Key': apiKey,
            if (gzipped) 'Content-Encoding': 'gzip',
          },
          body: body,
        )
        .timeout(timeout ?? this.timeout);
  }

  /// `Retry-After` as delay-seconds or an HTTP date. Null when absent or
  /// unreadable; a date in the past is zero.
  static Duration? retryAfterOf(String? header, {DateTime? now}) {
    final value = header?.trim();
    if (value == null || value.isEmpty) return null;
    final seconds = int.tryParse(value);
    if (seconds != null) {
      return seconds < 0 ? null : Duration(seconds: seconds);
    }
    final at = _parseHttpDate(value);
    if (at == null) return null;
    final wait = at.difference((now ?? DateTime.now()).toUtc());
    return wait.isNegative ? Duration.zero : wait;
  }

  static const _months = [
    'jan', 'feb', 'mar', 'apr', 'may', 'jun', //
    'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];

  /// IMF-fixdate (`Sun, 06 Nov 1994 08:49:37 GMT`). No `dart:io`, so this
  /// stays usable on the web.
  static DateTime? _parseHttpDate(String value) {
    final m = RegExp(
      r'^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
    ).firstMatch(value);
    if (m == null) return null;
    final month = _months.indexOf(m.group(2)!.toLowerCase()) + 1;
    if (month == 0) return null;
    return DateTime.utc(
      int.parse(m.group(3)!),
      month,
      int.parse(m.group(1)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
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
