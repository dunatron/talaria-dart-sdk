# Changelog

## Unreleased

- Lifecycle analytics: `Application Opened` on cold start and every foreground return, `Application Backgrounded` when the app leaves the foreground. Names are exported as `TalariaLifecycleEvents`. Gated by analytics consent like any other analytics call; pass `trackLifecycleEvents: false` to `TalariaFlutter.init` for tags only.

- Screen heatmaps no longer take continuous or mid-scroll screenshots. Capture is taps and scroll depth on the hot path; one idle fold PNG plus a structural tree uploads when the server requests a snapshot.
- Opportunistic tiles when the user naturally rests past the fold (no `jumpTo`). Up to three event-driven micro-frames on rage / dead / error taps.
- Stable ids via `TalariaHeatmapAnchor` or `Semantics.identifier`. Flutter Web uses the same raster snapshot path (no DOM).
- Dropped the 1Hz filmstrip and document `jumpTo` mosaic from the default heatmap path.
- Tap hit-testing skips walking every `Text` widget; the idle manifest still includes text nodes for the backdrop.

## 0.2.5

- Depends on `talaria` 0.3.6 (feature flags client).
- Lifecycle analytics: `Application Opened` / `Application Backgrounded` via `LifecycleObserver` (opt out with `trackLifecycleEvents: false`).

## 0.2.4

- Upload one snapshot per screen view, and skip the upload if the screen changes while the image is captured.
- Capture filmstrip frames only when a recording will be sent.

## 0.2.3

- Screen heatmaps via `TalariaScreenCapture`, with `TalariaHeatmapAnchor`, `TalariaMask`, and `TalariaUnmask`.
- Depends on `talaria` 0.3.4. Capture follows `heatmaps.enabled` and analytics in project settings.

## 0.2.2

- Stamp OS, device class, and (on web) browser fields onto analytics events.
- `sdk/getConfig` reports `platform: flutter`.

## 0.2.1

- Package docs point at the marketing guides.

## 0.2.0

- Depends on `talaria` 0.3.0. Tracing and analytics follow the project policy document.

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
