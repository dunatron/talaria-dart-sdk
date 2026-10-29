# Changelog

## 0.4.0

- Hard cut onto the locked `/v1` contract (platform PR #234 at `571c590c`).
- API keys are `tal_pk_<env>_<cell>_<43 base62><6 CRC32 base62>` or `tal_sk_…`, checksum alphabet `0-9A-Za-z`. `tal_live_` and class-less `tal_<env>_` keys are invalid. Monitor tokens (`tal_mon_…`) are not SDK api keys.
- The ingest URL is `https://ingest-<cell>.newtalaria.com` unless `url` or `TALARIA_URL` is set. A `self` cell fails fast without that override.
- A Dart VM / server client logs one warning when given a `tal_pk_` key.
- Auth is `Authorization: Bearer` only.
- Bodies are plain JSON. Batches are `{"events":[…]}`, `{"spans":[…]}`, `{"analytics":[…]}`, and `{"screenHeatmaps":[…]}`.
- `GET /v1/sdk-config`, `POST /v1/client-reports`, `POST /v1/flags/evaluate`, `GET /v1/flags` (definitions).
- Errors are RFC 9457 `application/problem+json` (`code`, `detail`, `requestId`, and `cell` / `url` on `wrong_cell`).
- CI release names replace `/` with `-` (`feature-x@a8f31c2`).

## 0.3.9

- Ingest and control calls send `Content-Encoding: gzip` JSON bodies (1 KB and up) once `sdk/getConfig` returns `capabilities.gzipRequests: true`. Older servers never advertise it, so they keep getting plain JSON. Web builds have no gzip codec and stay plain.
- The sends made by `close()` are never gzipped.
- If a server answers 415 to a gzipped body, the SDK resends that body plain and stops compressing until `getConfig` advertises gzip again.
- `capabilities.binaryUploads` is ignored: this SDK uploads no web replays or web heatmap snapshots. Screen heatmap PNGs still go base64 inside (now gzipped) JSON.

## 0.3.9

- Spans are exported in batches: on a full batch (`spanBatchSize`, default 200) or after `spanFlushIntervalMs` (default 5 s), at most `maxSpanExportsPerMinute` (default 30) automatic exports a minute, from a buffer of `maxSpanQueueSize` (default 2048) spans. Spans used to share `maxBatchSize` (50) and went out on every 2 s flush tick.
- The periodic flush no longer forces a span export. `flush()` and `close()` still send everything, and now wait for an export already in flight.
- `close()` leaves no span timer armed. `spanQueueSize()` reports spans waiting to export.
- With `flushIntervalMs: 0` the SDK still starts no timers, spans included: a due span batch goes out when the next span finishes, or on `flush()`/`close()`. Widget tests that set it to 0 keep passing the pending-timer check.
- Rate limits (HTTP 429): exports for that signal pause for at least `Retry-After` (else `retryAfterSeconds` in the body), growing exponentially on repeats up to 5 minutes, plus up to 20% jitter. The batch is kept and sent again after the pause. Items that overflow the buffer meanwhile are counted as `rate_limited`.
- Quota exhausted (HTTP 402 `ApiQuotaExceededException`): the batch is dropped as `quota`, not retried, and that signal (and the meter the body names) stops sending until the quota resets (body `resetAt`, else `Retry-After`, else 10 minutes). The SDK re-checks at most hourly, so a plan upgrade takes effect without a restart. New items are refused as `quota` while paused.
- Network errors, timeouts, 408 and 5xx: the batch is still dropped as `network`, and exports now back off exponentially with jitter (1 s doubling to 5 minutes).
- While a signal is paused, `flush()` sends nothing for it. `close()` counts anything still held as a discard.
- New discard reasons `rate_limited` and `quota`. A server that rejects them (400 `ApiValidationException`) gets only the older reasons from then on.
- `sdk/reportDiscards` has its own backoff and never reports on itself: a failed or rate-limited report is retried later, and makes no `onTransportError` call, no event, no span and no discard row.
- A rate-limited `sdk/getConfig` waits for `Retry-After` (at least 60 s) before refreshing.
- `TransportException` gains `retryAfter`, `resetAt`, `meter`, `isRateLimited`, `isQuotaExceeded` and `isTransient`. Rate limits are recognised by HTTP 429 or `ApiRateLimitedException`; the old 400 `ApiConflictException` `retry: true` shape is now just a transient error.
- `TalariaHttpClient.isTalariaIngestUrl` matches every SDK ingest and control call (`TalariaHttpClient.sdkEndpointMethods`): events `ingest`/`ingestBatch`, spans and analytics `ingestBatch`, `sdk/getConfig`, `sdk/reportDiscards`, `replays/ingestSegment*`, the heatmap and screen-heatmap uploads, and `flags/evaluate` / `flags/downloadDefinitions`. It matches `/<endpoint>/<method>` path segments, so a DSN with a path prefix still matches, and lookalike paths no longer do.
- Screen heatmap uploads (`sendScreenHeatmapBatch`, `uploadScreenHeatmapSnapshot`, `uploadScreenHeatmapRecording`) and flag reads (`flags/evaluate`, `flags/downloadDefinitions`) back off the same way, one pause for heatmaps and one for flags. After a 429 they wait for `Retry-After` plus jitter, growing up to 5 minutes. After a 402 they wait until `resetAt` (at most 1 hour, or 10 minutes when no reset is given). While paused they throw `IngestPausedException` (a `TransportException` whose `retryAfter` is the time left) without sending. `heatmapsPausedFor` and `flagsPausedFor` report the time left.
- A 402 on a heatmap upload counts as a `heatmaps`/`quota` discard (`DiscardSignal.heatmaps`). Rate-limited heatmap data stays with the caller, so it isn't counted. Flags report no discards. While paused they keep their last evaluations and log nothing.
- A 402 that names the `transactions` meter (the server's name for spans) or `analytics` now pauses that queue too. Before, only `events` and `spans` were matched.

## 0.3.8

- `RuntimeContext.zoneUrl` reads the URL bound on this Zone only. It ignores the isolate-wide fallback.
- `RuntimeContext.runWithAsync` takes `blankUnset`. When it is true, omitted request fields stay empty instead of inheriting a parent zone or the isolate, so one request cannot keep another's URL or user id.

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
