import 'package:flutter/widgets.dart';
import 'package:talaria/talaria.dart';

import 'screen_span.dart';

/// Sets `route` / `screen` tags and starts a short navigation transaction.
class TalariaNavigatorObserver extends NavigatorObserver {
  TalariaNavigatorObserver({
    TalariaClient? client,
    ScreenSpanController? screens,
  })  : _client = client ?? Talaria.getClient(),
        _screens = screens ?? ScreenSpanController.instance;

  final TalariaClient? _client;
  final ScreenSpanController _screens;
  String? _currentRoute;

  String? get currentRoute => _currentRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _update(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) {
      _update(newRoute);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) {
      _update(previousRoute);
    } else {
      _screens.finish();
    }
  }

  void _update(Route<dynamic> route) {
    final name = route.settings.name;
    final label =
        (name != null && name.isNotEmpty) ? name : route.runtimeType.toString();
    _currentRoute = label;
    _screens.start(label, client: _client ?? Talaria.getClient());
  }
}
