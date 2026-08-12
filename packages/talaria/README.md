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

## Shutdown

```dart
await Talaria.flush();
await Talaria.close();
```

## Notes

- Always uses `POST /events/ingestBatch` with `X-API-Key`
- Never computes fingerprints
- Main-isolate only in v1 — use Flutter package for framework hooks
