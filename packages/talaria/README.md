# talaria

[![pub package](https://img.shields.io/pub/v/talaria.svg)](https://pub.dev/packages/talaria)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/dunatron/talaria-dart-sdk/blob/main/LICENSE)

Official Dart SDK for [Talaria](https://www.newtalaria.com).

**Docs:** [Dart SDK](https://www.newtalaria.com/docs/sdk/dart) · [Project configuration](https://www.newtalaria.com/docs/configuration)

Flutter apps should use [`talaria_flutter`](https://www.newtalaria.com/docs/sdk/flutter). Serverpod 4 servers should add [`talaria_serverpod`](https://www.newtalaria.com/docs/sdk/serverpod).

## Install

```yaml
dependencies:
  talaria: ^0.3.7
```

## Initialize

The API key decides the environment.

```dart
import 'package:talaria/talaria.dart';

await Talaria.init(TalariaOptions(
  dsn: 'https://ingest.newtalaria.com',
  apiKey: const String.fromEnvironment('TALARIA_API_KEY'),
  release: '1.4.2',
  minLevel: SeverityLevel.warning,
));
```

Tracing and analytics follow Project settings.

## License

MIT
