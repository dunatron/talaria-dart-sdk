# talaria_flutter

Flutter bindings for [Talaria](https://www.newtalaria.com) — framework error hooks, zone bootstrap, navigator route tags, and lifecycle state.

Built on [`talaria`](../talaria).

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
| `TalariaNavigatorObserver` | `route` / `screen` tags |
| Lifecycle observer | `app.state` tag |
| `talariaErrorWidgetBuilder` | Build failures |

Events are tagged with `platform: flutter`.
