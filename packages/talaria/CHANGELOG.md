# Changelog

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
