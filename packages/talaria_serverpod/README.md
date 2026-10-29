# talaria_serverpod

[![pub package](https://img.shields.io/pub/v/talaria_serverpod.svg)](https://pub.dev/packages/talaria_serverpod)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/dunatron/talaria-dart-sdk/blob/main/LICENSE)

Serverpod 4 adapter for [Talaria](https://www.newtalaria.com). Same ingest contract as [`talaria`](https://pub.dev/packages/talaria): exceptions plus optional APM spans for endpoints, Postgres, and FutureCalls.

This package re-exports the core API. Add both `talaria` and `talaria_serverpod` to the server `pubspec`.

**Docs:** [Serverpod guide](https://www.newtalaria.com/docs/sdk/serverpod) · [Dart core](https://www.newtalaria.com/docs/sdk/dart) · [Flutter](https://pub.dev/packages/talaria_flutter)

Tracing and analytics follow [project configuration](https://www.newtalaria.com/docs/configuration).

## Install

```yaml
dependencies:
  talaria: ^0.4.0
  talaria_serverpod: ^0.3.0
  serverpod: ^4.0.0
```

Create a secret client key under **Project settings → Client keys** (`tal_sk_…`). Default keys include `events:write` and `spans:write`. A `tal_pk_` key logs one warning. The key's cell selects `https://ingest-<cell>.newtalaria.com` unless `url` or `TALARIA_URL` is set.

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
    apiKey: 'tal_sk_prod_nz1_…',
    release: '1.2.3',
    minLevel: SeverityLevel.warning,
    // tracing follows the project policy document
    tags: {'service': 'my_api'},
  ));

  TalariaServerpod.attach(pod);
  await pod.start();
}
```

Spans are sent in batches (see the `talaria` package's Span batching options), not after each request. `attach` registers a Serverpod shutdown task that flushes them when the server stops. If you shut down another way: `await Talaria.flush(); await Talaria.close();`.

## What is instrumented

| Surface | Span |
| --- | --- |
| Endpoint RPC + web routes | SERVER `{METHOD} {route}` — continues inbound W3C `traceparent` |
| Postgres / SQLite ORM and `unsafeQuery` | CLIENT `db.system.name`, sanitized SQL when available |
| FutureCalls | CONSUMER `FutureCall.{name}` (never adopted from another session) |
| Streaming methods | SERVER for the stream lifetime (not per chunk) |
| Uncaught diagnostics | One event per throw, isolated per session |
| Authenticated session | `enduser.id` / `user.id` on the session span |
| Outbound HTTP | `HttpClient` after init continues the active trace. `package:http` still uses `Talaria.wrapHttpClient` |

Skipped: ingest (`ingest` and `ingestBatch`), Insights, `/livez`, `/readyz`, `/startupz`, `/robots.txt`, `/favicon.ico`, and `/.well-known/`. Talaria SDK calls are skipped too (`TalariaServerpodPaths.sdkEndpointMethods`): `sdk/getConfig`, `sdk/reportDiscards`, `replays/ingestSegment*`, the heatmap and screen-heatmap uploads, and `flags/evaluate` / `flags/downloadDefinitions`. Other methods on those endpoints stay traced.

Skip more with `TalariaServerpod.attach(pod, skip: (url) => url.path.startsWith('/internal/'))`. To mount the middleware yourself, use `talariaRelicMiddleware(client, skip: ...)`.

ORM spans send a `db.query.text` stand-in (`SELECT Product`) when raw SQL is unavailable. Bind values are never sent. Repeated identical queries are each sent so N+1 stays visible.

## Outbound HTTP

`dart:io` `HttpClient` created after `TalariaServerpod.init` sends `traceparent` and records a client span while a request span is open. Ingest URLs are skipped. For `package:http`:

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

## License

MIT
