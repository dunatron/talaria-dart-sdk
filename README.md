# Talaria Dart / Flutter SDKs

Official client ingest SDKs for [Talaria](https://www.newtalaria.com).

| Package | Description |
| ------- | ----------- |
| [`talaria`](packages/talaria) | Pure Dart — facade, client, logger, batch HTTP transport, tracer, breadcrumbs |
| [`talaria_flutter`](packages/talaria_flutter) | Flutter — error hooks, zone bootstrap, navigator observer, lifecycle |

Fingerprinting stays on the server. Events go via `POST /events/ingestBatch`. When tracing is enabled, spans go via `POST /spans/ingestBatch`.

## Develop

```bash
cd packages/talaria && dart pub get && dart test
cd packages/talaria_flutter && flutter pub get && flutter test
```

## Docs

- [Dart guide](https://www.newtalaria.com/docs/sdk/dart)
- [Flutter guide](https://www.newtalaria.com/docs/sdk/flutter)
- [Logging levels](docs/logging-levels.md)
- Spec: `planning/dart_sdk_spec.md` in the Talaria meta-repo
