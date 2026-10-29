# talaria

[![pub package](https://img.shields.io/pub/v/talaria.svg)](https://pub.dev/packages/talaria)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/dunatron/talaria-dart-sdk/blob/main/LICENSE)

Official Dart SDK for [Talaria](https://www.newtalaria.com).

**Docs:** [Dart SDK](https://www.newtalaria.com/docs/sdk/dart) · [Project configuration](https://www.newtalaria.com/docs/configuration)

Flutter apps should use [`talaria_flutter`](https://www.newtalaria.com/docs/sdk/flutter). Serverpod 4 servers should add [`talaria_serverpod`](https://www.newtalaria.com/docs/sdk/serverpod).

## Install

```yaml
dependencies:
  talaria: ^0.3.7
```

## Initialize

The API key decides the environment.

```dart
import 'package:talaria/talaria.dart';

await Talaria.init(TalariaOptions(
  url: 'https://ingest.newtalaria.com',
  apiKey: const String.fromEnvironment('TALARIA_API_KEY'),
  release: '1.4.2',
  minLevel: SeverityLevel.warning,
));
```

Tracing and analytics follow Project settings.

## Span batching

Finished spans are sent in batches, not one request per traced call:

| Option | Default | What it does |
| --- | --- | --- |
| `spanBatchSize` | 200 | Spans per `/v1/spans` batch request (at most 200). A full batch goes out straight away. |
| `spanFlushIntervalMs` | 5000 | Longest a span waits before a partial batch is sent. `0` sends only full batches and explicit flushes. |
| `maxSpanExportsPerMinute` | 30 | Ceiling on automatic span requests a minute. The server allows 100 a minute per key by default. |
| `maxSpanQueueSize` | 2048 | Spans held while waiting. Beyond that they are dropped and reported as `queue_overflow`. |

`Talaria.flush()` and `Talaria.close()` still send everything at once, unless that signal is paused by a rate limit or quota (see below). With `flushIntervalMs: 0` (common in tests) the SDK starts no timers at all, so spans wait for a full or due batch at the next span, or for an explicit flush. Don't call `flush()` after every request on a long-running server; that is one export per request.

## Rate limits and quotas

Each signal (events, spans, analytics, discard reports) backs off on its own:

| Server reply | What the SDK does | Discard reason |
| --- | --- | --- |
| 429 rate limited | Pauses for at least `Retry-After`, exponential on repeats (to 5 min), plus jitter. Keeps the batch and sends it after the pause. | `rate_limited` if the buffer overflows meanwhile |
| 402 quota exhausted | Drops the batch, no retry. Stops sending that signal and the named meter until the reset time (re-checked hourly), or 10 minutes when the server gives none. | `quota` |
| Network error, timeout, 408, 5xx | Drops the batch. Backs off from 1 s, doubling to 5 min, with jitter. | `network` |

`flush()` doesn't override a pause. Failed discard reports never create events, spans, or `onTransportError` calls.

## License

MIT
