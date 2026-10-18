# Changelog

## 0.2.7

- The request middleware no longer flushes after every traced request. That sent one `spans/ingestBatch` per request and hit the default 100/min per-key limit at about 100 traced requests a minute. Spans are sent by the client's batch schedule; with `talaria` 0.3.9 that is at most 30 span exports a minute by default.
- `attach` registers a Serverpod shutdown task (`talaria.flush`) that flushes the client when the server stops. `registerShutdownFlush` does the same for apps that don't use `attach`.
- Talaria SDK ingest and control calls are never traced: `sdk/getConfig`, `sdk/reportDiscards`, `replays/ingestSegment*`, `heatmaps/ingestBatch` and `uploadSnapshot`, `screenHeatmaps/ingestBatch`, `uploadSnapshot` and `uploadRecording`, and `flags/evaluate` and `downloadDefinitions` (plus the existing `ingest`/`ingestBatch`). The list is `TalariaServerpodPaths.sdkEndpointMethods`, and `TalariaServerpodPaths.isSdkCall` checks it. Dashboard methods on those endpoints, and an app's own endpoints with the same names, stay traced.
- `TalariaServerpod.attach` takes `skip: bool Function(Uri url)` for more untraced requests.
- `talariaRelicMiddleware(client, {skip})` is exported from `package:talaria_serverpod/talaria_serverpod.dart`, so there's no need to import `src/relic_middleware.dart`.

## 0.2.6

- Depends on `talaria` 0.3.8. Request handling uses `RuntimeContext.zoneUrl` and `runWithAsync(blankUnset: true)`. Those members are not in the published `talaria` 0.3.7, so 0.2.5 does not compile against it.

## 0.2.5

- `HttpClient` created after `TalariaServerpod.init` continues the active request trace and sends `traceparent`. Ingest URLs stay unwrapped. Requests that already have `traceparent` are left alone. `Talaria.wrapHttpClient` still covers `package:http`.

## 0.2.4

- Depends on `talaria` 0.3.7.
- Removed `environment` from init. The API key decides the environment.

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
