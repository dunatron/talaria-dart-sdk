# Changelog

## 0.1.0

- Initial release: capture exceptions and logs via `POST /events/ingestBatch`.
- Optional tracing (off by default) with spans, breadcrumbs, and W3C `traceparent`.
- In-memory batching with `flush` / `close`; fingerprinting stays on the server.
