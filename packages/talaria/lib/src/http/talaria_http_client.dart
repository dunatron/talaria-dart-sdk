import 'package:http/http.dart' as http;

import '../client.dart';
import '../tracing/breadcrumbs.dart';
import '../tracing/span.dart';
import '../tracing/trace_context.dart';
import '../tracing/url_sanitizer.dart';

/// Wraps a user [http.Client] to emit client spans and inject `traceparent`.
///
/// Never wrap the ingest client used by `HttpTransport` — pass this wrapper
/// only to application HTTP (or give `HttpTransport` a separate span HTTP client).
/// Talaria ingest URLs are skipped even if wrapped by mistake.
class TalariaHttpClient extends http.BaseClient {
  TalariaHttpClient(
    http.Client inner, {
    TalariaClient? client,
  })  : _inner = inner,
        _client = client;

  final http.Client _inner;
  final TalariaClient? _client;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final client = _client;
    if (isTalariaIngestUrl(request.url) || client == null) {
      return _inner.send(request);
    }
    final sanitized = UrlSanitizer.sanitize(request.url);
    final method = request.method.toUpperCase();
    final path = UrlSanitizer.pathForName(sanitized);
    final start = DateTime.now().toUtc();

    final span = client.startSpan(
      '$method $path',
      kind: SpanKind.client,
      attributes: {
        'http.request.method': method,
        'url.path': path,
        if (sanitized.host.isNotEmpty) 'server.address': sanitized.host,
        if (sanitized.scheme.isNotEmpty) 'url.scheme': sanitized.scheme,
      },
    );

    if (span.isRecording) {
      request.headers.putIfAbsent(
        Traceparent.headerName,
        () => span.toTraceparent().toHeader(),
      );
      final requestId = client.currentRequestId;
      if (requestId != null &&
          requestId.isNotEmpty &&
          !request.headers.keys.any(
            (k) => k.toLowerCase() == 'x-request-id',
          )) {
        request.headers['X-Request-Id'] = requestId;
      }
    }

    http.StreamedResponse response;
    try {
      response = await _inner.send(request);
    } catch (e) {
      span.setAttribute('error.type', e.runtimeType.toString());
      span.markError(message: e.toString());
      span.finish(endTime: DateTime.now().toUtc());
      client.addBreadcrumb(Breadcrumb(
        type: 'http',
        category: 'http',
        message: '$method $path',
        level: 'error',
        data: {
          'http.request.method': method,
          'url.path': path,
          'error.type': e.runtimeType.toString(),
        },
        timestamp: start,
      ));
      rethrow;
    }

    final status = response.statusCode;
    span.setAttribute('http.response.status_code', status);
    if (status >= 500) {
      span.markError(message: 'HTTP $status');
    } else {
      span.setStatus(SpanStatus.ok);
    }
    span.finish(endTime: DateTime.now().toUtc());

    client.addBreadcrumb(Breadcrumb(
      type: 'http',
      category: 'http',
      message: '$method $path',
      level: status >= 500 ? 'error' : 'info',
      data: {
        'http.request.method': method,
        'url.path': path,
        'http.response.status_code': '$status',
      },
      timestamp: start,
    ));

    return response;
  }

  @override
  void close() => _inner.close();

  /// True for Talaria event/span ingest endpoints (must not be instrumented).
  static bool isTalariaIngestUrl(Uri uri) {
    final path = uri.path;
    return path.contains('/events/ingestBatch') ||
        path.contains('/spans/ingestBatch');
  }
}
