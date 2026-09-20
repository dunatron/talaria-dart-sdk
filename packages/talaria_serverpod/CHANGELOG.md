# Changelog

## 0.1.1

- Session roots no longer adopt another session's `currentSpan`. FutureCalls always start `FutureCall.{name}` CONSUMER.
- Drop the generic Serverpod "Internal server error. Request handler failed…" diagnostic duplicate.
- Uncaught Relic spans set `http.response.status_code=500`. HTTP 200 no longer clears a span already marked error.
- Authenticated `session` user is copied onto the session span as `enduser.id` / `user.id`.

## 0.1.0

- Initial Serverpod 4 adapter: Relic SERVER spans, `databaseInterceptor` Postgres CLIENT spans, FutureCall CONSUMER transactions, W3C `traceparent`.
- Tracing stays off until `TalariaOptions.enableTracing` or `tracesSampleRate > 0`.
