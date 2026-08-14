# talaria

Official Dart SDK for [Talaria](https://www.newtalaria.com) — capture exceptions and application logs into triageable issues.

Events are **queued in memory** and sent with batch ingest when the buffer hits a size limit, exceeds a max age, or you call `flush` / `close`. Fingerprinting stays on the server.

Docs: [Dart SDK guide](https://www.newtalaria.com/docs/sdk/dart) · Flutter: [`talaria_flutter`](../talaria_flutter) · Dashboard: [one.newtalaria.com](https://one.newtalaria.com)

## Install

```yaml
dependencies:
  talaria: ^0.1.0
```

## Initialize

Create a client key under **Project settings → Client keys** (`tal_live_…`).

```dart
import 'package:talaria/talaria.dart';

await Talaria.init(TalariaOptions(
  dsn: 'https://api.newtalaria.com',
  apiKey: 'tal_live_…',
  environment: 'production', // staging | development also accepted
  release: '1.4.2',
  commitSha: const String.fromEnvironment('TALARIA_COMMIT_SHA'),
  minLevel: SeverityLevel.warning,
  sampleRate: 1.0,
  tags: {
    'service': 'api',
    'platform': 'dart',
  },
));
```

Prefer `runZonedTalaria` (or `talaria_flutter`) so uncaught errors are captured:

```dart
final client = await Talaria.init(/* … */);
runZonedTalaria(client, () {
  // your app entry
});
```

## Logging

```dart
final logger = Talaria.logger(tags: {
  'feature': 'checkout',
  'operation': 'pay',
});

await logger.info('Checkout opened'); // filtered if minLevel is warning
await logger.warn('Payment method missing');

try {
  await charge();
} catch (e, st) {
  await logger.captureException(e, stackTrace: st, context: CaptureContext(
    tags: {'component': 'stripe'},
    extra: {'cart_id': 'abc123'},
  ));
  rethrow;
}
```

| Method | Severity sent |
| --- | --- |
| `debug` / `info` / `warning` / `error` / `fatal` | same name |
| `warn` | `warning` |
| `log(level, message)` | mapped severity |
| `captureException` | `error` |

## Filtering

Gates run in order. Filtered calls are quiet no-ops.

1. **`minLevel`** — default/root severity
2. **`sampleRate`** — fraction of eligible events to enqueue
3. **`beforeSend`** — return `null` to drop, or a mutated event

Scoped loggers may override below the root unless `enforceDefaultLevel` is true. Full rules: [logging-levels.md](../../docs/logging-levels.md).

## Tracing (APM)

Tracing is **off** until you set `enableTracing: true` or `tracesSampleRate > 0`. Successful transactions default to a 10% sample; error transactions are always sent.

```dart
await Talaria.init(TalariaOptions(
  dsn: 'https://api.newtalaria.com',
  apiKey: 'tal_live_…',
  environment: 'production',
  enableTracing: true, // 10% of successful transactions
  // tracesSampleRate: 0.25, // also enables tracing
));

final txn = Talaria.startTransaction('checkout');
try {
  final child = Talaria.startSpan('charge', kind: SpanKind.client);
  // …
  child.finish();
} catch (e, st) {
  txn.markError(message: e.toString());
  await Talaria.captureException(e, stackTrace: st);
  rethrow;
} finally {
  txn.finish();
}
```

Spans POST to `/spans/ingestBatch` (`IngestSpanBatchInput`). Events stay on `/events/ingestBatch`.

### Outbound HTTP

Wrap **application** `package:http` clients. Never wrap the ingest client used by `HttpTransport` (or pass a separate `spanHttpClient` for span POSTs).

```dart
final httpClient = Talaria.wrapHttpClient(http.Client());
final response = await httpClient.get(Uri.parse('https://api.partner.dev/v1/pay'));
```

This starts a client span, injects W3C `traceparent`, and records an HTTP breadcrumb. Talaria ingest URLs are skipped if wrapped by mistake. `Talaria.getTraceparent()` returns the active header when a span is recording.

There is no `talaria_dio` package. For Dio, wrap the adapter's `http.Client` with `TalariaHttpClient`, or add an interceptor that calls `Talaria.startSpan` / injects `traceparent`. Use `addProcessor` for per-request `url` / `requestId` / tags on a shared client:

```dart
Talaria.addProcessor((bag) {
  return {
    ...bag,
    'url': currentRequestUrl,
    'requestId': currentRequestId,
  };
});
```

### Breadcrumbs

A ring buffer of 50 breadcrumbs is attached on error events, with `traceId` / `spanId` when a span is in scope.

```dart
Talaria.addBreadcrumb(Breadcrumb(
  type: 'user',
  category: 'ui',
  message: 'Tapped Pay',
));
```

## Shutdown

```dart
await Talaria.flush();
await Talaria.close();
```

## Notes

- Events: `POST /events/ingestBatch` with `X-API-Key`
- Spans: `POST /spans/ingestBatch` when tracing is enabled
- Never computes fingerprints
- Main-isolate only in v1 — use Flutter package for framework hooks
