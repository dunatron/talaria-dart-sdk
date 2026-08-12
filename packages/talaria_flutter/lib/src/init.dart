import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:talaria/talaria.dart';

import 'lifecycle_observer.dart';

typedef _PlatformErrorHandler = bool Function(Object error, StackTrace stack);

/// Flutter-specific bootstrap helpers for Talaria.
class TalariaFlutter {
  TalariaFlutter._();

  static LifecycleObserver? _lifecycle;
  static bool _hooksInstalled = false;
  static FlutterExceptionHandler? _previousFlutterOnError;
  static _PlatformErrorHandler? _previousPlatformOnError;

  /// Initialize Talaria for Flutter and install framework error hooks.
  ///
  /// Sets `platform: flutter` on all events.
  static Future<TalariaClient> init(
    TalariaOptions options, {
    Transport? transport,
    bool installHooks = true,
    bool observeLifecycle = true,
  }) async {
    final flutterOptions = TalariaOptions(
      dsn: options.baseUrl,
      apiKey: options.apiKey,
      environment: options.environment,
      release: options.release,
      commitSha: options.commitSha,
      sampleRate: options.sampleRate,
      maxBatchSize: options.maxBatchSize,
      flushIntervalMs: options.flushIntervalMs,
      defaultIntegrations: false,
      userId: options.userId,
      tags: {
        ...options.tags,
        'flutter': 'true',
      },
      httpTimeoutSeconds: options.httpTimeoutSeconds,
      minLevel: options.minLevel,
      enforceDefaultLevel: options.enforceDefaultLevel,
      loggers: options.loggers,
      beforeSend: options.beforeSend,
      platform: 'flutter',
    );

    final client = await Talaria.init(flutterOptions, transport: transport);
    client.platformOverride = 'flutter';

    if (installHooks) {
      installErrorHooks(client);
    }
    if (observeLifecycle) {
      WidgetsFlutterBinding.ensureInitialized();
      _lifecycle?.dispose();
      _lifecycle = LifecycleObserver(client)..register();
    }

    return client;
  }

  /// Wire [FlutterError.onError] and [PlatformDispatcher.instance.onError].
  static void installErrorHooks(TalariaClient client) {
    if (_hooksInstalled) {
      return;
    }
    _hooksInstalled = true;

    _previousFlutterOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      // ignore: discarded_futures
      client.captureException(
        details.exception,
        stackTrace: details.stack,
        context: const CaptureContext(
          mechanism: ExceptionMechanism(
            type: 'flutter_error',
            handled: false,
          ),
        ),
      );
      final previous = _previousFlutterOnError;
      if (previous != null) {
        previous(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    _previousPlatformOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      // ignore: discarded_futures
      client.captureException(
        error,
        stackTrace: stack,
        context: const CaptureContext(
          mechanism: ExceptionMechanism(
            type: 'platform_dispatcher',
            handled: false,
          ),
        ),
      );
      final previous = _previousPlatformOnError;
      if (previous != null) {
        return previous(error, stack);
      }
      return true;
    };
  }

  /// Recommended entrypoint: binding + init + zone + Flutter [runApp].
  ///
  /// Returns once the app widget tree has been scheduled. Zone errors after
  /// return continue to be captured via the installed hooks and the zone.
  static Future<void> runZonedApp(
    TalariaOptions options,
    Widget app, {
    Transport? transport,
  }) {
    final started = Completer<void>();

    runZonedGuarded(() async {
      WidgetsFlutterBinding.ensureInitialized();
      await init(options, transport: transport);
      runApp(app);
      if (!started.isCompleted) {
        started.complete();
      }
    }, (Object error, StackTrace stack) {
      final client = Talaria.getClient();
      if (client != null) {
        // ignore: discarded_futures
        client.captureException(
          error,
          stackTrace: stack,
          context: const CaptureContext(
            mechanism: ExceptionMechanism(
              type: 'zone',
              handled: false,
            ),
          ),
        );
      } else {
        debugPrint('[Talaria] early zone error: $error\n$stack');
      }
      if (!started.isCompleted) {
        started.completeError(error, stack);
      }
    });

    return started.future;
  }

  /// Tear down Flutter observers and close the SDK.
  static Future<void> close() async {
    _lifecycle?.dispose();
    _lifecycle = null;
    if (_hooksInstalled) {
      FlutterError.onError = _previousFlutterOnError;
      PlatformDispatcher.instance.onError = _previousPlatformOnError;
      _previousFlutterOnError = null;
      _previousPlatformOnError = null;
      _hooksInstalled = false;
    }
    await Talaria.close();
  }
}
