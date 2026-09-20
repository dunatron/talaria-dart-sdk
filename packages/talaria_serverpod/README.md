# talaria_serverpod

[![pub package](https://img.shields.io/pub/v/talaria_serverpod.svg)](https://pub.dev/packages/talaria_serverpod)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/dunatron/talaria-dart-sdk/blob/main/LICENSE)

Serverpod 4 adapter for [Talaria](https://www.newtalaria.com). Same ingest contract as [`talaria`](https://pub.dev/packages/talaria): exceptions plus optional APM spans for endpoints, Postgres, and FutureCalls.

This package re-exports the core API. Add both `talaria` and `talaria_serverpod` to the server `pubspec`.

**Docs:** [Serverpod guide](https://www.newtalaria.com/docs/sdk/serverpod) · [Dart core](https://www.newtalaria.com/docs/sdk/dart) · [Flutter](https://pub.dev/packages/talaria_flutter)

Tracing is **off** until `enableTracing: true` or `tracesSampleRate > 0`.

## Install

```yaml
dependencies:
  talaria: ^0.2.3
  talaria_serverpod: ^0.1.3
  serverpod: ^4.0.0
```

Create a client key under **Project settings → Client keys** (`tal_live_…`). Default keys include `eventsWrite` and `spansWrite`.

## Wire it

Pass `databaseInterceptor` to the `Serverpod` constructor — Serverpod does not allow swapping it later. `interceptDatabase` no-ops until `TalariaServerpod.init` and until tracing is on.

```dart
import 'package:serverpod/serverpod.dart';
import 'package:talaria_serverpod/talaria_serverpod.dart';

void run(List<String> args) async {
  final pod = Serverpod(
    args,
    Protocol(),
    Endpoints(),
    databaseInterceptor: TalariaServerpod.interceptDatabase,
    experimentalFeatures: ExperimentalFeatures(
      diagnosticEventHandlers: [
        AsEventHandler<ExceptionEvent>((event, {required space, required context}) {
          TalariaServerpod.handleExceptionEvent(event);
        }),
      ],
    ),
  );

  await TalariaServerpod.init(TalariaOptions(
    dsn: 'https://api.newtalaria.com',
    apiKey: 'tal_live_…',
    environment: 'production',
    release: '1.2.3',
    minLevel: SeverityLevel.warning,
    enableTracing: true,
    tags: {'service': 'my_api'},
  ));

  TalariaServerpod.attach(pod);
  await pod.start();
}
```

On shutdown: `await Talaria.flush(); await Talaria.close();`.

## What is instrumented

| Surface | Span |
| --- | --- |
| Endpoint RPC + web routes | SERVER `{METHOD} {route}` — continues inbound W3C `traceparent` |
| Postgres / SQLite ORM and `unsafeQuery` | CLIENT `db.system.name`, sanitized SQL when available |
| FutureCalls | CONSUMER `FutureCall.{name}` (never adopted from another session) |
| Streaming methods | SERVER for the stream lifetime (not per chunk) |
| Uncaught diagnostics | One event per throw, isolated per session |
| Authenticated session | `enduser.id` / `user.id` on the session span |
| Outbound HTTP | Use `Talaria.wrapHttpClient` (skip ingest URLs) |

Skipped: `events/ingestBatch`, `spans/ingestBatch`, Insights, `/livez`, `/readyz`, `/startupz`.

ORM spans send a `db.query.text` stand-in (`SELECT Product`) when raw SQL is unavailable. Bind values are never sent. Repeated identical queries are each sent so N+1 stays visible.

## Outbound HTTP

```dart
final httpClient = Talaria.wrapHttpClient(http.Client());
```

Never wrap the SDK ingest client. Redis and other caches are opt-in — wrap them with `Talaria.startSpan`.

## Manual spans

```dart
final span = Talaria.startSpan('charge', kind: SpanKind.client);
try {
  await charge();
  span.setStatus(SpanStatus.ok);
} catch (e, st) {
  span.markError(message: e.toString());
  await Talaria.captureException(e, stackTrace: st);
  rethrow;
} finally {
  span.finish();
}
```

See the [`talaria`](https://pub.dev/packages/talaria) README for logger levels, sampling, breadcrumbs, and `getTraceparent()`.

## Dashboard

Spans use the same wire as the other official SDKs. The customer **Performance** UI (waterfall, dependencies, slow queries, RED) shows them.

## What this package does not do

- Host / Kubernetes metrics, `pg_stat_statements`, or EXPLAIN
- Bind values on SQL
- Continuous profiling
- Session replay (browser SDK)
- OTLP export — use the Collector path in the [API overview](https://www.newtalaria.com/docs/api) if you already operate one

## License

MIT
