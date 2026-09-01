# talaria_flutter

Flutter bindings for [Talaria](https://www.newtalaria.com) — framework error hooks, zone bootstrap, navigator route tags, and lifecycle state.

Built on [`talaria`](https://pub.dev/packages/talaria).

Docs: [Flutter guide](https://www.newtalaria.com/docs/sdk/flutter)

## Install

```yaml
dependencies:
  talaria_flutter: ^0.1.0
```

## Bootstrap

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

Or use the all-in-one helper:

```dart
Future<void> main() async {
  await TalariaFlutter.runZonedApp(
    TalariaOptions(
      dsn: 'https://api.newtalaria.com',
      apiKey: 'tal_live_…',
      environment: 'production',
    ),
    const MyApp(),
  );
}
```

## What you get

| Integration | Behavior |
| --- | --- |
| `FlutterError.onError` | Framework errors → `captureException` |
| `PlatformDispatcher.onError` | Platform/async errors |
| Zone (via `runApp` helper) | Uncaught zone errors |
| `TalariaNavigatorObserver` | `route` / `screen` tags and a navigation transaction on push/pop |
| Lifecycle observer | `app.state` tag |
| `talariaErrorWidgetBuilder` | Build failures |

Events are tagged with `platform: flutter`.

## Tracing

Pass `enableTracing: true` (or `tracesSampleRate > 0`) in `TalariaOptions`. The navigator observer starts a transaction per route. Wrap application HTTP with `Talaria.wrapHttpClient` — do not wrap Talaria's ingest client.

There is no `talaria_dio` package; intercept Dio via a wrapped `http.Client` or `addProcessor`.

See the [`talaria`](https://pub.dev/packages/talaria) README for span ingest, sampling, breadcrumbs, and W3C `traceparent`.
