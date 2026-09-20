# talaria_flutter

[![pub package](https://img.shields.io/pub/v/talaria_flutter.svg)](https://pub.dev/packages/talaria_flutter)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/dunatron/talaria-dart-sdk/blob/main/LICENSE)

Flutter bindings for [Talaria](https://www.newtalaria.com) — framework error hooks, zone bootstrap, navigator route tags, and lifecycle state.

Built on [`talaria`](https://pub.dev/packages/talaria). This package re-exports the core API, so you do not add `talaria` as a direct dependency unless you share a Dart library across targets.

**Docs:** [Flutter guide](https://www.newtalaria.com/docs/sdk/flutter) · [Dart core](https://www.newtalaria.com/docs/sdk/dart) · [Serverpod](https://pub.dev/packages/talaria_serverpod)

## Install

```yaml
dependencies:
  talaria_flutter: ^0.1.3
```

## Bootstrap

`TalariaFlutter.init` installs framework hooks and tracks `app.state`. Add `TalariaNavigatorObserver` so events carry `route` / `screen`.

```dart
import 'package:flutter/material.dart';
import 'package:talaria_flutter/talaria_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await TalariaFlutter.init(TalariaOptions(
    dsn: const String.fromEnvironment(
      'TALARIA_DSN',
      defaultValue: 'https://api.newtalaria.com',
    ),
    apiKey: const String.fromEnvironment('TALARIA_API_KEY'),
    environment: const String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'development',
    ),
    release: const String.fromEnvironment('APP_RELEASE'),
    minLevel: SeverityLevel.warning,
    enableTracing: true,
  ));

  ErrorWidget.builder = talariaErrorWidgetBuilder();

  runApp(MyApp(
    navigatorObservers: [TalariaNavigatorObserver()],
  ));
}
```

Or wrap init and `runApp` in a zone so async errors outside the framework are captured too:

```dart
Future<void> main() async {
  await TalariaFlutter.runZonedApp(
    TalariaOptions(
      dsn: 'https://api.newtalaria.com',
      apiKey: 'tal_live_…',
      environment: 'production',
      minLevel: SeverityLevel.warning,
      enableTracing: true,
    ),
    const MyApp(),
  );
}
```

`runZonedApp` installs `ErrorWidget.builder` for you. Pass `TalariaNavigatorObserver` on your `MaterialApp` / `CupertinoApp` either way.

Never hardcode keys. Map flavors and `--dart-define` into `environment` and `release`.

## What you get

| Integration | Behavior |
| --- | --- |
| `FlutterError.onError` | Framework errors → `captureException` |
| `PlatformDispatcher.onError` | Platform / async errors |
| Zone (via `runZonedApp`) | Uncaught zone errors |
| `TalariaNavigatorObserver` | `route` / `screen` tags and a short page-load transaction (finishes on idle) |
| `TalariaFlutter.setScreen` | Same short span for IndexedStack / tab destinations |
| Lifecycle observer | `app.state` tag |
| `talariaErrorWidgetBuilder` | Build failures (one event; installed by `runZonedApp`) |
| Runtime extras | locale, OS, and on web the renderer / user agent |

Events are tagged with `platform: flutter`.

## Navigation and screen spans

`TalariaNavigatorObserver` starts an **INTERNAL** transaction named after the route and finishes it on the next idle frame (10s cap). That keeps a shell route from parenting every later HTTP call.

For `IndexedStack`, `TabBar`, or other hosts that do not push routes:

```dart
TalariaFlutter.setScreen('/lab');
```

## Capture

The core facade is re-exported. Prefer a scoped logger and `captureException` with a stack:

```dart
try {
  await riskyOperation();
} catch (error, stackTrace) {
  await Talaria.captureException(
    error,
    stackTrace: stackTrace,
    context: CaptureContext(tags: {'screen': 'checkout'}),
  );
  rethrow;
}
```

See the [`talaria`](https://pub.dev/packages/talaria) README for logger levels, tags vs extra, `beforeSend`, breadcrumbs, and processors.

## Tracing

Pass `enableTracing: true` (or `tracesSampleRate > 0`) in `TalariaOptions`. Tracing is **off** until you do. Successful transactions default to 10%; error transactions are always sent.

Wrap **application** HTTP with `Talaria.wrapHttpClient`. Do not wrap Talaria’s ingest client.

```dart
final httpClient = Talaria.wrapHttpClient(http.Client());
```

There is no `talaria_dio` package. Intercept Dio via a wrapped `http.Client` or `Talaria.startSpan` / `getTraceparent()`.

When this app talks to a Serverpod API that also runs Talaria, outbound `traceparent` continues the Flutter screen or HTTP span on the server. See [`talaria_serverpod`](https://pub.dev/packages/talaria_serverpod) and [W3C trace context](https://www.newtalaria.com/learn/w3c-trace-context).

Session replay and Web Vitals are browser-SDK features. This package does not record them.

## Shutdown

```dart
await TalariaFlutter.close();
```

## License

MIT
