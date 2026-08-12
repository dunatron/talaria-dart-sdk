# Talaria Dart / Flutter SDKs

Official client ingest SDKs for [Talaria](https://www.newtalaria.com).

| Package | Description |
| ------- | ----------- |
| [`talaria`](packages/talaria) | Pure Dart — facade, client, logger, batch HTTP transport |
| [`talaria_flutter`](packages/talaria_flutter) | Flutter — error hooks, zone bootstrap, navigator observer, lifecycle |

Fingerprinting stays on the server. Events are queued and sent via `POST /events/ingestBatch`.

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
