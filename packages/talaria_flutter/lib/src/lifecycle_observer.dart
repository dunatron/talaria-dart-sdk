import 'package:flutter/widgets.dart';
import 'package:talaria/talaria.dart';

/// Stable analytics event names for app lifecycle.
///
/// These strings are the wire contract — dashboards, funnels, and experiments
/// reference them by name, so they must not be renamed or localised.
class TalariaLifecycleEvents {
  TalariaLifecycleEvents._();

  /// Cold start and every return to the foreground.
  static const opened = 'Application Opened';

  /// The app left the foreground (paused, hidden, or detached).
  static const backgrounded = 'Application Backgrounded';
}

/// Updates `app.state` tags from [AppLifecycleState] changes, and emits the
/// lifecycle analytics events when analytics is on.
///
/// The analytics events are gated exactly like any other analytics call: they
/// need `enableAnalytics` (or `analytics.optIn()`), so a consent-gated app emits
/// nothing until the user opts in. `inactive` is ignored because it fires for
/// transient interruptions such as the app switcher or a notification shade.
class LifecycleObserver with WidgetsBindingObserver {
  LifecycleObserver(this._client, {bool trackAnalytics = true})
      : _trackAnalytics = trackAnalytics;

  final TalariaClient _client;
  final bool _trackAnalytics;
  bool _registered = false;
  bool _foreground = false;

  void register() {
    if (_registered) {
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _registered = true;
    _apply(WidgetsBinding.instance.lifecycleState);
  }

  void dispose() {
    if (!_registered) {
      return;
    }
    WidgetsBinding.instance.removeObserver(this);
    _registered = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _apply(state);
  }

  void _apply(AppLifecycleState? state) {
    if (state == null) {
      return;
    }
    _client.setTags({'app.state': state.name});
    _trackLifecycle(state);
  }

  void _trackLifecycle(AppLifecycleState state) {
    if (!_trackAnalytics || !_client.analytics.isEnabled) {
      return;
    }
    switch (state) {
      case AppLifecycleState.resumed:
        if (_foreground) return;
        _foreground = true;
        _track(TalariaLifecycleEvents.opened);
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (!_foreground) return;
        _foreground = false;
        _track(TalariaLifecycleEvents.backgrounded);
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _track(String name) {
    // ignore: discarded_futures
    _client.analytics.track(name);
  }
}
