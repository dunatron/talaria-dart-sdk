# talaria

[![pub package](https://img.shields.io/pub/v/talaria.svg)](https://pub.dev/packages/talaria)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/dunatron/talaria-dart-sdk/blob/main/LICENSE)

Official Dart SDK for [Talaria](https://www.newtalaria.com) — capture exceptions and application logs into triageable issues, with optional APM spans.

Events queue in memory and flush on batch size, max age, or `flush` / `close`. Fingerprinting stays on the server. A permanent ingest error (`retry: false`, such as an invalid API key) stops further event and span sends for this process; quota and 5xx do not.

**Docs:** [Dart SDK](https://www.newtalaria.com/docs/sdk/dart) · [Flutter](https://pub.dev/packages/talaria_flutter) · [Serverpod](https://pub.dev/packages/talaria_serverpod) · [Dashboard](https://one.newtalaria.com)

## Install

```yaml
dependencies:
  talaria: ^0.2.4
```

Building a Flutter app? Use [`talaria_flutter`](https://pub.dev/packages/talaria_flutter) instead — it re-exports this package and installs framework hooks. Building a Serverpod 4 server? Add [`talaria_serverpod`](https://pub.dev/packages/talaria_serverpod) for endpoint, database, and FutureCall tracing.

## Initialize

Create a client key under **Project settings → Client keys** (`tal_live_…`). Default keys include `eventsWrite` and `spansWrite`.

```dart
import 'package:talaria/talaria.dart';

await Talaria.init(TalariaOptions(
  dsn: 'https://api.newtalaria.com',
  apiKey: const String.fromEnvironment('TALARIA_API_KEY'),
  environment: 'production', // staging | development also accepted
  release: '1.4.2',
  commitSha: const String.fromEnvironment('TALARIA_COMMIT_SHA'),
  minLevel: SeverityLevel.warning,
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

Never hardcode keys. Prefer `--dart-define`, environment variables, or your secret store.

## Capture exceptions

```dart
try {
  await charge();
} catch (error, stackTrace) {
  await Talaria.captureException(
    error,
    stackTrace: stackTrace,
    context: CaptureContext(
      tags: {'feature': 'checkout', 'component': 'payments'},
      extra: {'cart_id': 'cart_01H…'},
    ),
  );
  rethrow;
}
```

`captureException` always sends severity `error`. `captureMessage` defaults to `info`.

## Scoped logging

Prefer a scoped logger in application code. Level methods wrap `captureMessage`; use `captureException` for errors.

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

// Child scopes inherit tags. Assigned minLevel may raise or lower the floor
// unless enforceDefaultLevel is true.
final payments = logger.child(
  tags: {'component': 'payments'},
  minLevel: SeverityLevel.error,
);
await payments.error('Charge failed');
```

| Method | Severity sent |
| --- | --- |
| `debug` / `info` / `warning` / `error` / `fatal` | same name |
| `warn` | `warning` |
| `log(level, message)` | mapped severity |
| `captureException` | `error` |

### Tags vs extra

- **`tags`** — low-cardinality filters (`feature`, `operation`, `component`). These become dashboard facets.
- **`extra`** — high-cardinality diagnostics (`cart_id`, payloads). Do not put unique ids in tags.

### Level hierarchy

Client `minLevel` is the default/root. A scoped logger may assign a different floor (more or less verbose). Set `enforceDefaultLevel: true` to restore a hard floor (`max(root, scope)`).

Gates run in order. Filtered calls are quiet no-ops.

1. **`minLevel`** — default/root severity
2. **`sampleRate`** — fraction of eligible **events** to enqueue (not traces)
3. **`beforeSend`** — return `null` to drop, or a mutated event

```dart
await Talaria.init(TalariaOptions(
  dsn: 'https://api.newtalaria.com',
  apiKey: 'tal_live_…',
  environment: 'production',
  minLevel: SeverityLevel.warning,
  ignoreErrors: [RegExp(r'SocketException')],
  ignoreUrls: ['/health'],
  beforeSend: (event, hint) {
    if (event.message.toLowerCase().contains('password')) return null;
    return event;
  },
  loggers: {
    'checkout': LoggerPreset(
      minLevel: SeverityLevel.info,
      tags: {'area': 'checkout'},
    ),
  },
));
```

## User and request context

```dart
Talaria.getClient()?.setUser('user_01H…');
Talaria.addProcessor((bag) {
  return {
    ...bag,
    'url': currentRequestUrl,
    'requestId': currentRequestId,
  };
});
```

`setTags` / `setExtra` / `setUser` live on `TalariaClient` for mutable global context after init.

## Breadcrumbs

A ring buffer of 50 breadcrumbs is attached on error events, with `traceId` / `spanId` when a span is in scope.

```dart
Talaria.addBreadcrumb(Breadcrumb(
  type: 'user',
  category: 'ui',
  message: 'Tapped Pay',
));
```

## Tracing (APM)

Turn tracing on in the project first (`tracingEnabled`), then set `enableTracing: true` or `tracesSampleRate > 0` in the SDK. Successful transactions default to a 10% sample; **error** transactions are always sent. Child spans are stored, not billed — only sampled root transactions count toward the plan quota. There is no separate Performance add-on.

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
  try {
    await charge();
    child.setStatus(SpanStatus.ok);
  } finally {
    child.finish();
  }
} catch (e, st) {
  txn.markError(message: e.toString());
  await Talaria.captureException(e, stackTrace: st);
  rethrow;
} finally {
  txn.finish();
}
```

| API | Role |
| --- | --- |
| `startTransaction` | New trace root. Optional W3C `Traceparent` parent for distributed continuation. |
| `startSpan` | Child of the current span (or a new root if none). |
| `SpanKind` | `internal`, `server`, `client`, `producer`, `consumer` |
| `SpanStatus` | `unset`, `ok`, `error` |
| `markError` | Marks the span and force-samples the trace |

A trace holds at most 200 spans; further `startSpan` calls return a no-op. When tracing is off, both APIs return `NoOpSpan`.

Spans POST to `/spans/ingestBatch`. Events stay on `/events/ingestBatch`.

### Outbound HTTP

Wrap **application** `package:http` clients. Never wrap the ingest client used by `HttpTransport`.

```dart
final httpClient = Talaria.wrapHttpClient(http.Client());
final response = await httpClient.get(Uri.parse('https://api.partner.dev/v1/pay'));
```

This starts a client span, injects W3C `traceparent`, and records an HTTP breadcrumb. Talaria ingest URLs are skipped if wrapped by mistake. `Talaria.getTraceparent()` returns the active header when a span is recording.

There is no `talaria_dio` package. For Dio, wrap the adapter's `http.Client` with `TalariaHttpClient`, or add an interceptor that calls `Talaria.startSpan` and injects `traceparent`.

SQL helpers (`SqlSanitizer`, `DbSpan`) and concurrent `SpanScope` live in this package for servers that wrap their own stores. Flutter and Serverpod adapters call them for you.

## Analytics

Consent is **off** until `enableAnalytics: true` or `Talaria.analytics.optIn()`. There is no click autocapture.

```dart
await Talaria.init(TalariaOptions(
  dsn: 'https://api.newtalaria.com',
  apiKey: 'tal_live_…',
  environment: 'production',
  enableAnalytics: true,
));

await Talaria.analytics.identify('user_123', traits: {'plan': 'team'});
await Talaria.analytics.track('product_viewed', properties: {
  'product_id': '123',
  'price': 129.99,
});
await Talaria.analytics.page();
await Talaria.analytics.screen();
await Talaria.analytics.reset();
```

On Dart servers, pass `userId` and/or `anonymousId` on each call (or bind them on `RuntimeContext`) so requests are not mixed. Flutter persists `anonymousId` and rotates `sessionId` after 30 minutes idle or midnight UTC. Analytics POST to `/analytics/ingestBatch`.

## Shutdown

```dart
await Talaria.flush();
await Talaria.close();
```

Call this from process shutdown (and Serverpod / isolate teardown) so the last batch leaves the queue.

## What this package does not do

- Fingerprints — computed on the server
- Session replay or native crash dumps
- Host / Kubernetes metrics or continuous profiling
- Automatic Flutter or Serverpod hooks — use the adapter packages
- Click autocapture

## License

MIT
