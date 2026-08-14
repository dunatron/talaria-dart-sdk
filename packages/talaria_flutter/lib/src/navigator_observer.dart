import 'package:flutter/widgets.dart';
import 'package:talaria/talaria.dart';

/// Sets `route` / `screen` tags and starts a navigation transaction per route.
class TalariaNavigatorObserver extends NavigatorObserver {
  TalariaNavigatorObserver({TalariaClient? client})
      : _client = client ?? Talaria.getClient();

  final TalariaClient? _client;
  String? _currentRoute;
  Span? _routeSpan;

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
      _finishRouteSpan();
    }
  }

  void _update(Route<dynamic> route) {
    final name = route.settings.name;
    final label =
        (name != null && name.isNotEmpty) ? name : route.runtimeType.toString();
    _currentRoute = label;

    RuntimeContext.setUrl(label);

    final client = _client ?? Talaria.getClient();
    client?.setTags({
      'route': label,
      'screen': label,
    });
    client?.addBreadcrumb(Breadcrumb(
      type: 'navigation',
      category: 'navigation',
      message: label,
      data: {'ui.screen.name': label},
    ));

    _finishRouteSpan();
    _routeSpan = client?.startTransaction(
      label,
      kind: SpanKind.internal,
      attributes: {
        'ui.screen.name': label,
      },
    );
    final span = _routeSpan;
    if (span != null && span.isRecording) {
      RuntimeContext.setRequestId(span.spanId);
    }
  }

  void _finishRouteSpan() {
    final span = _routeSpan;
    if (span == null) {
      return;
    }
    if (span.isRecording) {
      span.setStatus(SpanStatus.ok);
      span.finish();
    }
    _routeSpan = null;
  }
}
