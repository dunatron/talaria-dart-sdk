import 'package:serverpod/serverpod.dart';
import 'package:talaria/talaria.dart';

import 'paths.dart';
import 'relic_span_finish.dart';

/// Relic middleware: SERVER transaction per request + W3C `traceparent`.
Middleware talariaRelicMiddleware(TalariaClient client) {
  return (Handler innerHandler) {
    return (Request req) async {
      if (!client.tracer.isEnabled || TalariaServerpodPaths.isNoisy(req.url)) {
        return innerHandler(req);
      }

      return SpanScope.runAsync(() async {
        final method = req.method.value;
        final route = TalariaServerpodPaths.httpRoute(req.url);
        final incoming = Traceparent.tryParse(
          req.headers[Traceparent.headerName]?.firstOrNull,
        );
        final span = client.startTransaction(
          '$method $route',
          kind: SpanKind.server,
          attributes: {
            'http.request.method': method,
            'http.route': route,
            'url.path': req.url.path.isEmpty ? '/' : req.url.path,
          },
          parent: incoming,
        );
        RuntimeContext.setCurrent(
          url: req.url.toString(),
          requestId: incoming?.traceId ?? span.spanId,
        );
        client.addBreadcrumb(Breadcrumb(
          type: 'http',
          category: 'http',
          message: '$method $route',
          level: 'info',
          data: {'http.request.method': method, 'http.route': route},
        ));

        try {
          final result = await innerHandler(req);
          if (result is Response) {
            RelicSpanFinish.onResponse(span, result.statusCode);
          } else {
            RelicSpanFinish.onResponse(span, null);
          }
          return result;
        } catch (e) {
          RelicSpanFinish.onThrow(span, e);
          rethrow;
        } finally {
          span.finish();
          await client.flush();
        }
      });
    };
  };
}
