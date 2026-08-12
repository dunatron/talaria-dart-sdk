import 'package:flutter/widgets.dart';
import 'package:talaria/talaria.dart';

/// Updates `app.state` tags from [AppLifecycleState] changes.
class LifecycleObserver with WidgetsBindingObserver {
  LifecycleObserver(this._client);

  final TalariaClient _client;
  bool _registered = false;

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
  }
}
