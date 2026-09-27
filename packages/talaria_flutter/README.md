# talaria_flutter

[![pub package](https://img.shields.io/pub/v/talaria_flutter.svg)](https://pub.dev/packages/talaria_flutter)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/dunatron/talaria-dart-sdk/blob/main/LICENSE)

Flutter bindings for [Talaria](https://www.newtalaria.com). Re-exports [`talaria`](https://pub.dev/packages/talaria).

**Docs:** [Flutter guide](https://www.newtalaria.com/docs/sdk/flutter) · [Project configuration](https://www.newtalaria.com/docs/configuration)

## Install

```yaml
dependencies:
  talaria_flutter: ^0.2.3
```

## Bootstrap

```dart
import 'package:flutter/material.dart';
import 'package:talaria_flutter/talaria_flutter.dart';

Future<void> main() async {
  await TalariaFlutter.runZonedApp(
    TalariaOptions(
      dsn: 'https://ingest.newtalaria.com',
      apiKey: const String.fromEnvironment('TALARIA_API_KEY'),
      environment: 'production',
      minLevel: SeverityLevel.warning,
    ),
    const MyApp(),
  );
}
```

Pass `TalariaNavigatorObserver` on `MaterialApp`. Tracing and analytics follow Project settings.

## Screen heatmaps

Wrap the app once. Taps, scroll depth, and masked snapshots upload when the project has analytics and heatmaps enabled.

```dart
TalariaScreenCapture(
  child: MaterialApp(
    navigatorObservers: [TalariaNavigatorObserver()],
    home: const HomePage(),
  ),
)
```

`TalariaMask` covers a subtree in the snapshot. `TalariaHeatmapAnchor` gives a control a stable id.

## License

MIT
