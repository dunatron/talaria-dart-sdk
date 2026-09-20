# Talaria Dart SDKs

Official [Talaria](https://www.newtalaria.com) ingest SDKs for Dart, Flutter, and Serverpod 4.

Talaria turns production exceptions into triageable issues and sampled transactions into waterfalls and RED metrics. Fingerprinting stays on the server. Events go to `POST /events/ingestBatch`. When tracing is enabled, spans go to `POST /spans/ingestBatch`.

| Package | Role | Docs |
| --- | --- | --- |
| [`talaria`](https://pub.dev/packages/talaria) | Core Dart SDK — capture, logging, breadcrumbs, optional tracing | [Dart guide](https://www.newtalaria.com/docs/sdk/dart) |
| [`talaria_flutter`](https://pub.dev/packages/talaria_flutter) | Flutter hooks — errors, navigation, lifecycle | [Flutter guide](https://www.newtalaria.com/docs/sdk/flutter) |
| [`talaria_serverpod`](https://pub.dev/packages/talaria_serverpod) | Serverpod 4 — endpoints, Postgres, FutureCalls | [Serverpod guide](https://www.newtalaria.com/docs/sdk/serverpod) |

Pick one package for your surface. Flutter and Serverpod re-export the core API, so you do not add `talaria` twice unless you share a Dart library across targets.

## Which package?

- **CLI, VM, or shared Dart library** — `talaria`
- **Flutter app** — `talaria_flutter` (includes the core SDK)
- **Serverpod 4 server** — `talaria` + `talaria_serverpod`

Tracing is **off** until you set `enableTracing: true` or `tracesSampleRate > 0`. Existing error-only apps keep sending events only.

## Develop

```bash
cd packages/talaria && dart pub get && dart test
cd packages/talaria_flutter && flutter pub get && flutter test
cd packages/talaria_serverpod && dart pub get && dart test
```

## License

MIT. See [LICENSE](LICENSE).
