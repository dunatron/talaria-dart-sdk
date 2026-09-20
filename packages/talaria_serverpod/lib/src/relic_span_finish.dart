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

  static void onThrow(Span span, Object error) {
    span.setAttribute('http.response.status_code', 500);
    span.markError(message: error.toString());
  }
}
