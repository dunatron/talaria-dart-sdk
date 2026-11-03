# talaria

[![pub package](https://img.shields.io/pub/v/talaria.svg)](https://pub.dev/packages/talaria)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/dunatron/talaria-dart-sdk/blob/main/LICENSE)

Official Dart SDK for [Talaria](https://www.newtalaria.com).

**Docs:** [Dart SDK](https://www.newtalaria.com/docs/sdk/dart) · [Project configuration](https://www.newtalaria.com/docs/configuration)

Flutter apps should use [`talaria_flutter`](https://www.newtalaria.com/docs/sdk/flutter). Serverpod 4 servers should add [`talaria_serverpod`](https://www.newtalaria.com/docs/sdk/serverpod).

## Install

```yaml
dependencies:
  talaria: ^0.4.1
```

## Initialize

The API key's cell decides the ingest host (`https://ingest-<cell>.newtalaria.com`) unless `url` or `TALARIA_URL` is set. A `self` cell without one of those disables Talaria. Server and CI keys are `tal_sk_…` (`TALARIA_API_KEY`). The key must match the §5.1 grammar, including the CRC32 base62 checksum.

```dart
import 'dart:io';

import 'package:talaria/talaria.dart';

await Talaria.init(TalariaOptions(
  apiKey: Platform.environment['TALARIA_API_KEY']!,
  release: '1.4.2',
  minLevel: SeverityLevel.warning,
));
```

A publishable `tal_pk_` key is accepted on the Dart VM and logs one warning: ingest works, but releases, flag definitions, and monitor check-ins need a `tal_sk_` key. Flutter init refuses `tal_sk_` and `tal_mon_` keys by disabling Talaria.

Init never throws. A missing, empty, malformed or wrong-checksum key, a `tal_mon_` token, or a bad option gives a disabled no-op client: one `[Talaria] Talaria is disabled: …` warning per process (showing at most the first 8 characters of the key), no network, and every call returns normally. `Talaria.isEnabled` and `client.disabledReason` tell you why. Transport errors (401, 5xx, timeouts, network) are swallowed and logged at most once a minute per channel.

Requests use `Authorization: Bearer`. Batches are plain JSON `{"events":[…]}`, `{"spans":[…]}`, and `{"analytics":[…]}`. Policy is `GET /v1/sdk-config`. Discard reports are `POST /v1/client-reports`. Flag evaluation is `POST /v1/flags/evaluate`. Errors are `application/problem+json`.

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
