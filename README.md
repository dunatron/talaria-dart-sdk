# Talaria Dart / Flutter SDKs

Official client ingest SDKs for [Talaria](https://www.newtalaria.com).

| Package | Description |
| ------- | ----------- |
| [`talaria`](packages/talaria) | Pure Dart — facade, client, logger, batch HTTP transport, tracer, breadcrumbs |
| [`talaria_flutter`](packages/talaria_flutter) | Flutter — error hooks, zone bootstrap, navigator observer, lifecycle |
| [`talaria_serverpod`](packages/talaria_serverpod) | Serverpod 4 — endpoint, Postgres, and FutureCall tracing |

Fingerprinting stays on the server. Events go via `POST /events/ingestBatch`. When tracing is enabled, spans go via `POST /spans/ingestBatch`.

## Develop

```bash
cd packages/talaria && dart pub get && dart test
cd packages/talaria_flutter && flutter pub get && flutter test
cd packages/talaria_serverpod && dart pub get && dart test
```

## Docs

- [Dart guide](https://www.newtalaria.com/docs/sdk/dart)
- [Flutter guide](https://www.newtalaria.com/docs/sdk/flutter)
- [Serverpod guide](docs/serverpod.md)
- [Logging levels](docs/logging-levels.md)
- Spec: `planning/dart_sdk_spec.md` in the Talaria meta-repo
