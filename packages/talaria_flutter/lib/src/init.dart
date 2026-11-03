import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:talaria/talaria.dart';

import 'flutter_runtime.dart';
import 'flutter_web_info_stub.dart'
    if (dart.library.js_interop) 'flutter_web_info_web.dart' as web_info;
import 'heatmaps/session.dart';
import 'lifecycle_observer.dart';
import 'screen_span.dart';
import 'shared_preferences_storage.dart';
import 'widgets/error_widget.dart';

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
  /// Sets `platform: flutter` on all events. Never throws: a missing or
  /// invalid key (including a `tal_sk_` or `tal_mon_` key, which Flutter
  /// refuses) returns a disabled no-op client, warns once, and installs no
  /// hooks or observers. The app keeps running.
  static Future<TalariaClient> init(
    TalariaOptions options, {
    Transport? transport,
    bool installHooks = true,
    bool observeLifecycle = true,
    bool trackLifecycleEvents = true,
  }) async {
    try {
      return await _initUnsafe(
        options,
        transport: transport,
        installHooks: installHooks,
        observeLifecycle: observeLifecycle,
        trackLifecycleEvents: trackLifecycleEvents,
      );
    } catch (error) {
      // Talaria must never break the host app (D19).
      return Talaria.init(
        TalariaOptions(
          apiKey: '',
          platform: 'flutter',
          disabledReason: 'Flutter init failed ($error)',
        ),
      );
    }
  }

  static Future<TalariaClient> _initUnsafe(
    TalariaOptions options, {
    Transport? transport,
    required bool installHooks,
    required bool observeLifecycle,
    required bool trackLifecycleEvents,
  }) async {
    final credential = options.credential;
    if (options.enabled && credential != null && !credential.isPublishable) {
      final preview = FailSafe.keyPreview(options.apiKey);
      return Talaria.init(
        TalariaOptions(
          apiKey: '',
          platform: 'flutter',
          disabledReason: 'The API key ($preview) is not a tal_pk_ key. '
              'Flutter accepts only publishable keys '
              '(--dart-define=TALARIA_BROWSER_API_KEY); tal_sk_ and tal_mon_ '
              'keys are refused',
        ),
      );
    }
    if (!options.enabled) {
      return Talaria.init(options.copyWith(platform: 'flutter'));
    }

    TalariaStorage? storage = options.storage;
    if (storage == null) {
      try {
        storage = await SharedPreferencesTalariaStorage.create();
      } catch (_) {
        storage = MemoryTalariaStorage();
      }
    }

    final flutterOptions = options.copyWith(
      platform: 'flutter',
      tags: {...options.tags, 'flutter': 'true'},
      defaultIntegrations: false,
      storage: storage,
    );

    final client = await Talaria.init(flutterOptions, transport: transport);
    if (!client.isEnabled) {
      return client;
    }
    client.platformOverride = 'flutter';
    client.analytics.contextProvider = () {
      final page = web_info.browserPageContext();
      return AnalyticsPageContext(
        url: page?.url ?? RuntimeContext.url,
        path: page?.path ?? RuntimeContext.url,
        title: page?.title,
        referrer: page?.referrer,
      );
    };
    FlutterRuntime.enrich(client);

    if (installHooks) {
      installErrorHooks(client);
    }
    if (observeLifecycle) {
      WidgetsFlutterBinding.ensureInitialized();
      _lifecycle?.dispose();
      _lifecycle = LifecycleObserver(
        client,
        trackAnalytics: trackLifecycleEvents,
      )..register();
    }

    return client;
  }

  /// Wire [FlutterError.onError] and [PlatformDispatcher.instance.onError].
  ///
  /// The hooks never throw: a Talaria fault is swallowed and the previous
  /// handler always runs. A disabled client installs nothing.
  static void installErrorHooks(TalariaClient client) {
    if (_hooksInstalled || !client.isEnabled) {
      return;
    }
    _hooksInstalled = true;

    _previousFlutterOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!isWidgetBuildError(details)) {
        _report(
          client,
          details.exception,
          details.stack,
          const CaptureContext(
            mechanism: ExceptionMechanism(
              type: 'flutter_error',
              handled: false,
            ),
          ),
        );
      }
      final previous = _previousFlutterOnError;
      if (previous != null) {
        previous(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    _previousPlatformOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _report(
        client,
        error,
        stack,
        const CaptureContext(
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

  /// Report [error] without ever throwing into the caller.
  static void _report(
    TalariaClient client,
    Object error,
    StackTrace? stack,
    CaptureContext context,
  ) {
    try {
      // ignore: discarded_futures
      client
          .captureException(error, stackTrace: stack, context: context)
          .catchError((Object e) {
        FailSafe.logRateLimited('flutter-hook', '[Talaria] capture failed: $e');
      });
      ScreenHeatmapController.instance.noteError();
    } catch (e) {
      FailSafe.logRateLimited('flutter-hook', '[Talaria] capture failed: $e');
    }
  }

  /// Recommended entrypoint: binding + init + zone + Flutter [runApp].
  ///
  /// Returns once the app widget tree has been scheduled. Zone errors after
  /// return continue to be captured via the installed hooks and the zone.
  /// A bad key never stops [app] from running: Talaria is just disabled.
  static Future<void> runZonedApp(
    TalariaOptions options,
    Widget app, {
    Transport? transport,
  }) {
    final started = Completer<void>();

    runZonedGuarded(
      () async {
        WidgetsFlutterBinding.ensureInitialized();
        var enabled = false;
        try {
          final client = await init(options, transport: transport);
          enabled = client.isEnabled;
        } catch (error) {
          FailSafe.warnDisabledOnce('Flutter init failed ($error)');
        }
        if (enabled) {
          ErrorWidget.builder = talariaErrorWidgetBuilder();
        }
        runApp(app);
        if (!started.isCompleted) {
          started.complete();
        }
      },
      (Object error, StackTrace stack) {
        final client = Talaria.getClient();
        if (client != null && client.isEnabled) {
          _report(
            client,
            error,
            stack,
            const CaptureContext(
              mechanism: ExceptionMechanism(type: 'zone', handled: false),
            ),
          );
        } else {
          debugPrint('[Talaria] early zone error: $error\n$stack');
        }
        if (!started.isCompleted) {
          started.completeError(error, stack);
        }
      },
    );

    return started.future;
  }

  /// Short INTERNAL screen span + breadcrumb for IndexedStack / tab hosts.
  static void setScreen(String name, {TalariaClient? client, String? title}) {
    ScreenSpanController.instance.start(name, client: client, title: title);
    ScreenHeatmapController.instance.setManualScreen(name);
  }

  /// Whether [details] will also be reported by [ErrorWidget.builder].
  static bool isWidgetBuildError(FlutterErrorDetails details) {
    final library = details.library ?? '';
    final context = details.context?.toDescription() ?? '';
    return library == 'widgets library' ||
        context.toLowerCase().contains('building');
  }

  /// Tear down Flutter observers and close the SDK.
  static Future<void> close() async {
    ScreenSpanController.instance.finish();
    _lifecycle?.dispose();
    _lifecycle = null;
    RuntimeContext.clearCurrent();
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
