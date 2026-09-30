# Changelog

## 0.2.3

- Depends on `talaria` 0.3.6. Mid-request flag helper via `TalariaServerpodFlags`.

## 0.2.2

- Depends on `talaria` 0.3.2.
- Skip probe and ingest paths (`/robots.txt`, `/favicon.ico`, `/.well-known/`, `ingest` and `ingestBatch`) so they do not become transactions.
- Client results (not-found, unauthorized, conflict, quota, rate limit) stay HTTP 4xx spans with status ok.
- Drop quota, rate-limit, and "project not found" diagnostics before they become issues.
- FutureCall spans that finish cleanly are status ok.

## 0.2.1

- Package docs point at the marketing guides.

## 0.2.0

- Depends on `talaria` 0.3.0. Tracing follows the project policy document.

## 0.1.3

- Documentation: public README rewrite; no API changes.

## 0.1.2

- Drop expected Serverpod diagnostics (`ApiUnauthorizedException`, websocket close) and isolate request URL / breadcrumbs / userId on capture.

## 0.1.1

- Session roots no longer adopt another session's `currentSpan`. FutureCalls always start `FutureCall.{name}` CONSUMER.
- Drop the generic Serverpod "Internal server error. Request handler failed…" diagnostic duplicate.
- Uncaught Relic spans set `http.response.status_code=500`. HTTP 200 no longer clears a span already marked error.
- Authenticated `session` user is copied onto the session span as `enduser.id` / `user.id`.

## 0.1.0

- Initial Serverpod 4 adapter: Relic SERVER spans, `databaseInterceptor` Postgres CLIENT spans, FutureCall CONSUMER transactions, W3C `traceparent`.
- Tracing stays off until `TalariaOptions.enableTracing` or `tracesSampleRate > 0`.
