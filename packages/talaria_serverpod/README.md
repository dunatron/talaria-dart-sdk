# talaria_serverpod

Serverpod 4 adapter for [Talaria](https://www.newtalaria.com). Same ingest contract as [`talaria`](https://pub.dev/packages/talaria) and the Silverstripe PHP module: errors plus optional APM spans.

Tracing is **off** until `enableTracing: true` or `tracesSampleRate > 0`.

## Install

```yaml
dependencies:
  talaria: ^0.2.2
  talaria_serverpod: ^0.1.2
  serverpod: ^4.0.0
```

## Wire it

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
    enableTracing: true, // default false
    tags: {'service': 'my_api'},
  ));

  TalariaServerpod.attach(pod);
  await pod.start();
}
```

Pass `databaseInterceptor` at construction — Serverpod does not allow swapping it later. `interceptDatabase` no-ops until init and until tracing is on.

## What is instrumented

| Surface | Span |
| --- | --- |
| Endpoint RPC + web routes | SERVER `POST /{endpoint}/{method}` |
| Postgres / SQLite ORM and `unsafeQuery` | CLIENT `db.system.name`, sanitized SQL when available |
| FutureCalls | CONSUMER `FutureCall.{name}` (never adopted from another session) |
| Streaming methods | SERVER for the stream lifetime |
| Uncaught diagnostics | One event per throw (`serverpod_diagnostic`; generic wrapper dropped) |
| Outbound HTTP | Use `Talaria.wrapHttpClient` (skip ingest URLs) |

Ingest (`events/ingestBatch`, `spans/ingestBatch`), Insights, and health probes are skipped.

## Outbound HTTP

```dart
final httpClient = Talaria.wrapHttpClient(http.Client());
```

Never wrap the SDK ingest client. Redis and other caches are opt-in — wrap them yourself with `Talaria.startSpan`.

## Docs

- [Serverpod guide](../../docs/serverpod.md)
- [Dart core](../talaria)
