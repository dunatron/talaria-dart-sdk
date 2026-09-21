# Changelog

## 0.1.4

- Persist `anonymousId` / session ids with SharedPreferences.
- Auto `$screen` (and `$pageview` on Flutter web) from `TalariaNavigatorObserver` when analytics is enabled.

## 0.1.3

- Documentation: public README rewrite; no API changes.

## 0.1.2

- Navigation transactions finish on the next idle frame (10s cap) so a shell route cannot parent every RPC.
- `TalariaFlutter.setScreen` starts the same short INTERNAL span for IndexedStack / tab hosts.
- Widget build failures are captured once (`error_widget`); `runZonedApp` installs `ErrorWidget.builder`.
- Flutter runtime extra includes locale, OS, and (on web) renderer / user agent.

## 0.1.1

- Allow `talaria` 0.2.x so apps can share the core SDK with `talaria_serverpod`.

## 0.1.0

- Initial Flutter bindings on `talaria`: error hooks, zone bootstrap, navigator observer, and lifecycle tags.
- Optional tracing via `TalariaOptions.enableTracing` / `tracesSampleRate`.
