# talaria_flutter

[![pub package](https://img.shields.io/pub/v/talaria_flutter.svg)](https://pub.dev/packages/talaria_flutter)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/dunatron/talaria-dart-sdk/blob/main/LICENSE)

Flutter bindings for [Talaria](https://www.newtalaria.com). Re-exports [`talaria`](https://pub.dev/packages/talaria).

**Docs:** [Flutter guide](https://www.newtalaria.com/docs/sdk/flutter) · [Project configuration](https://www.newtalaria.com/docs/configuration)

## Install

```yaml
dependencies:
  talaria_flutter: ^0.2.6
```

## Bootstrap

The API key decides the environment.

```dart
import 'package:flutter/material.dart';
import 'package:talaria_flutter/talaria_flutter.dart';

Future<void> main() async {
  await TalariaFlutter.runZonedApp(
    TalariaOptions(
      dsn: 'https://ingest.newtalaria.com',
      apiKey: const String.fromEnvironment('TALARIA_API_KEY'),
      minLevel: SeverityLevel.warning,
    ),
    const MyApp(),
  );
}
```

Pass `TalariaNavigatorObserver` on `MaterialApp`. Tracing and analytics follow Project settings.

## Screen heatmaps

Wrap the app once. Continuous capture is taps and scroll depth only (no periodic screenshots). When the project has analytics and heatmaps enabled, the server may ask for one idle fold snapshot after settle. If the user rests deeper in a scroll, that viewport may be stored as a tile (no forced scroll). Rage / dead / error taps may attach up to three short micro-frames.

```dart
TalariaScreenCapture(
  child: MaterialApp(
    navigatorObservers: [TalariaNavigatorObserver()],
    home: const HomePage(),
  ),
)
```

The fold snapshot matches the rendered screen. Password fields are covered. `TalariaHeatmapPrivacy(maskInputs: true)` also covers other text fields, and `maskText` / `maskImages` cover text and images. `TalariaMask` always covers a subtree. `TalariaUnmask` opts that subtree back out.

### Stable control names

`TalariaHeatmapAnchor(id: 'checkout_pay')` or `Semantics(identifier: 'checkout_pay', …)` give a control a stable id in the element list. Otherwise the name is the control's label. Typed field values are not stored.

### Flutter Web

Capture uses the same API on Flutter Web (CanvasKit / Skwasm). There is no DOM snapshot path — the idle fold still uses `toImage`. Prefer short settle time and modest pixel density; embedded platform views may appear blank in the PNG.

## License

MIT
