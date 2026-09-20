# Serverpod guide

Set up Talaria on **Serverpod 4** with `talaria` + `talaria_serverpod`. The core package is framework-agnostic; this adapter is the Silverstripe equivalent for Serverpod (Relic middleware, `databaseInterceptor`, FutureCalls).

Tracing is **off** until `enableTracing: true` or `tracesSampleRate > 0`. When enabled without an explicit rate, successful transactions sample at **10%**; **error** transactions are always sent.

## Install

```yaml
dependencies:
  talaria: ^0.2.1
  talaria_serverpod: ^0.1.1
  serverpod: ^4.0.0
```

Create a client key under **Project settings → Client keys** (`tal_live_…`). Default app keys include `eventsWrite` + `spansWrite`.

## Wire it

`databaseInterceptor` must be passed to the `Serverpod` constructor. It no-ops until `TalariaServerpod.init` and until tracing is on.

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
    enableTracing: true, // default false
    tags: {'service': 'my_api'},
  ));

  TalariaServerpod.attach(pod);
  await pod.start();
}
```

On shutdown, `await Talaria.flush(); await Talaria.close();`.

## What is instrumented

| Signal | How |
| --- | --- |
| Incoming RPC / HTTP | Relic middleware — SERVER span (`http.request.method`, `http.route`, `http.response.status_code`). Continues W3C `traceparent` |
| Postgres / SQLite | `databaseInterceptor` wraps ORM + `unsafeQuery` as CLIENT spans (`db.system.name`, `db.operation.name`, sanitized `db.query.text` when SQL is available). Repeated identical queries are each sent (N+1 stays visible) |
| FutureCalls | CONSUMER `FutureCall.{name}` — always its own root, never the current stream/RPC span |
| Streaming methods | SERVER span for the stream lifetime (not per chunk) |
| Uncaught errors | `DiagnosticEventHandler` → events with `traceId` / `spanId` + breadcrumbs |
| Outbound HTTP | `Talaria.wrapHttpClient` — never wrap the ingest client |

Skipped: `events/ingestBatch`, `spans/ingestBatch`, Insights, `/livez` `/readyz` `/startupz`.

## Outbound HTTP

```dart
final httpClient = Talaria.wrapHttpClient(http.Client());
```

Redis and other caches are **not** auto-wired (same as Silverstripe). Start a CLIENT span around the calls you care about.

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

## Dashboard

Spans use the same wire as PHP / Flutter. The customer **Performance** UI (waterfall, dependencies, slow queries, RED) shows them — there is no separate Serverpod metrics product.

## Non-goals

Host / k8s metrics, `pg_stat_statements`, EXPLAIN, bind values on SQL, continuous profiling, OTLP export from this SDK.
