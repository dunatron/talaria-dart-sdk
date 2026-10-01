# Changelog

## 0.3.7

- Event, span, and analytics payloads no longer include `environment`. The API key decides it. `init` still accepts the argument so code built against 0.3.6 compiles; the value is not sent.
- `sdk/getConfig` waits 5 seconds. A slower policy response still enables heatmaps and analytics.
- Identical SQL under one parent is one span with `db.query.count` and `db.query.duration_sum_ms`. The span stays the slowest execution. Queries of 200ms or more, and failed queries, stay their own spans.
- A trace stores at most 200 spans and keeps 32 slots for non-SQL spans. The root records `dropped_span_count` when a span is dropped.
- `withoutQuerySpans` and `setRecordQuerySpans(false)` turn automatic SQL spans off for one run.
- Query breadcrumbs use at most 15 of the 50 breadcrumb slots.

## 0.3.6

- Feature flags: `Talaria.flags` with `boolVariation` / `stringVariation` / `jsonVariation`, `setContext`, disk cache, TTL poll, and `loadDefinitions` for local evaluation.
- Stamp up to 20 `flag.<key>` tags on events, spans, and analytics. Optional `$feature_flag_called` once per key per session.
- Apply `flags.enabled` from `sdk/getConfig`.

## 0.3.5

- Screen heatmap snapshot and recording uploads wait up to 20 seconds. The default ingest timeout was cutting off the PNG before the API stored it.

## 0.3.4

- Flutter screen heatmaps: `sendScreenHeatmapBatch`, `uploadScreenHeatmapSnapshot`, and `uploadScreenHeatmapRecording`.
- Apply `heatmaps.enabled` from `sdk/getConfig`. Taps are not analytics events.

## 0.3.3

- Stamp `device`, `osName`, `osVersion`, and (when known) browser fields on analytics events.
- `Talaria.setUser`, `anonymousId`, and `sessionId` on the static facade.
- Honor `ingest.*.state: paused` from `sdk/getConfig`.
- Report discard counts to `sdk/reportDiscards` (`sample_rate`, `queue_overflow`, `signal_disabled`, `network`).
- Refresh the project policy document on `ttlSeconds` in a long-lived isolate.
- `getConfig` sends `sdkVersion` and the client's `platform` (`dart` or `flutter`).

## 0.3.2

- Span and event timestamps keep sub-millisecond precision when the clock has it.

## 0.3.1

- Package docs point at the marketing guides.

## 0.3.0

- Tracing and analytics follow `POST /sdk/getConfig`. Until that document is cached, the SDK sends errors only.
- A disabled signal stops that signal. A rejected key stops the isolate.

## 0.2.4

- Durable `anonymousId` and session rotation (30 minutes idle or midnight UTC) via a storage port; Flutter persists with SharedPreferences.
- Product analytics (`Talaria.analytics`) with consent default off (`enableAnalytics` / `optIn`), batch ingest to `/analytics/ingestBatch`.
- Stamp `anonymousId` on event and span payloads.

## 0.2.3

- Documentation: public README rewrite; no API changes.

## 0.2.2

- Disable event and span ingest for the process after a permanent client error (`retry: false` / invalid API key). Quota and 5xx keep sending.
- Sanitize generated `_…Impl` exception type names in payloads.

## 0.2.1

- Deny `package:serverpod*`, `package:relic*`, and `package:talaria*` frames in `inApp`.
- ORM-style spans include a `db.query.text` stand-in (`SELECT Product`) when raw SQL is unavailable.
- Copy `userId` from the current span (`enduser.id` / `user.id`) and `userAgent` from `RuntimeContext` onto events and finished spans.
- Expose `Span.status` and `Span.getAttribute`.

## 0.2.0

- SQL sanitizer, `DbSpan`, and concurrent [SpanScope] for multi-session servers.
- `ignoreErrors` / `ignoreUrls` on `TalariaOptions` (Sentry substring/regex semantics).
- Optional `userAgent` on the event wire payload.

## 0.1.0

- Initial release: capture exceptions and logs via `POST /events/ingestBatch`.
- Optional tracing (off by default) with spans, breadcrumbs, and W3C `traceparent`.
- In-memory batching with `flush` / `close`; fingerprinting stays on the server.
