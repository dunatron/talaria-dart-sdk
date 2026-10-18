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
  dsn: 'https://ingest.newtalaria.com',
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
| `spanBatchSize` | 200 | Spans per `spans/ingestBatch` request (at most 200). A full batch goes out straight away. |
| `spanFlushIntervalMs` | 5000 | Longest a span waits before a partial batch is sent. `0` sends only full batches and explicit flushes. |
| `maxSpanExportsPerMinute` | 30 | Ceiling on automatic span requests a minute. The server allows 100 a minute per key by default. |
| `maxSpanQueueSize` | 2048 | Spans held while waiting. Beyond that they are dropped and reported as `queue_overflow`. |

`Talaria.flush()` and `Talaria.close()` still send everything at once. With `flushIntervalMs: 0` (common in tests) the SDK starts no timers at all, so spans wait for a full or due batch at the next span, or for an explicit flush. Don't call `flush()` after every request on a long-running server; that is one export per request.

## License

MIT
