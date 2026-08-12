import 'package:flutter/widgets.dart';
import 'package:talaria/talaria.dart';

/// Sets `route` / `screen` tags from navigator transitions.
class TalariaNavigatorObserver extends NavigatorObserver {
  TalariaNavigatorObserver({TalariaClient? client})
      : _client = client ?? Talaria.getClient();

  final TalariaClient? _client;
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
    }
  }

  void _update(Route<dynamic> route) {
    final name = route.settings.name;
    final label = (name != null && name.isNotEmpty)
        ? name
        : route.runtimeType.toString();
    _currentRoute = label;
    final client = _client ?? Talaria.getClient();
    client?.setTags({
      'route': label,
      'screen': label,
    });
  }
}
