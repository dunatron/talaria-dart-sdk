import 'package:talaria/talaria.dart';

/// Relic SERVER span status / HTTP attributes.
class RelicSpanFinish {
  RelicSpanFinish._();

  static void onResponse(Span span, int? statusCode) {
    if (statusCode != null) {
      span.setAttribute('http.response.status_code', statusCode);
      if (statusCode >= 500) {
        span.markError(message: 'HTTP $statusCode');
        return;
      }
    }
    if (span.status != SpanStatus.error) {
      span.setStatus(SpanStatus.ok);
    }
  }

  /// HTTP status when [error] is a client result (4xx), not a server failure.
  static int? clientErrorStatus(Object error) {
    final type = error.runtimeType.toString();
    if (type.contains('NotFound')) return 404;
    if (type.contains('Unauthorized') || type.contains('NotAuthorized')) {
      return 401;
    }
    if (type.contains('QuotaExceeded') || type.contains('RateLimit')) {
      return 429;
    }
    if (type.contains('Conflict')) return 409;
    if (type.contains('BadRequest')) return 400;
    final message = error.toString().toLowerCase();
    if (message.contains('no method name specified') ||
        message.contains('endpoint dispatch error')) {
      return 404;
    }
    return null;
  }

  static void onThrow(Span span, Object error) {
    final clientStatus = clientErrorStatus(error);
    if (clientStatus != null) {
      span.setAttribute('http.response.status_code', clientStatus);
      if (span.status != SpanStatus.error) {
        span.setStatus(SpanStatus.ok);
      }
      return;
    }
    span.setAttribute('http.response.status_code', 500);
    span.markError(message: error.toString());
  }
}
