import 'dart:async';
import 'dart:developer' as developer;

import '../capture_context.dart';
import '../client.dart';

/// Marker for default Dart integrations.
///
/// Uncaught-error capture is performed via [runZonedTalaria] (or Flutter
/// helpers). This class exists so `defaultIntegrations: true` has a clear
/// register/unregister lifecycle matching other Talaria SDKs.
class ZoneIntegration {
  ZoneIntegration();

  bool _registered = false;

  void register() {
    _registered = true;
  }

  void unregister() {
    _registered = false;
  }

  bool get isRegistered => _registered;
}

/// Run [body] in a zone that reports uncaught errors to [client].
R? runZonedTalaria<R>(
  TalariaClient client,
  R Function() body,
) {
  return runZonedGuarded(
    body,
    (error, stack) {
      // ignore: discarded_futures
      client
          .captureException(
        error,
        stackTrace: stack,
        context: const CaptureContext(
          mechanism: ExceptionMechanism(
            type: 'zone',
            handled: false,
          ),
        ),
      )
          .catchError((Object e, StackTrace st) {
        developer.log(
          '[Talaria] zone capture failed: $e',
          name: 'talaria',
          error: e,
          stackTrace: st,
        );
      });
    },
  );
}
