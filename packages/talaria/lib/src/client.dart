import 'dart:async';
import 'dart:developer' as developer;

import 'capture_context.dart';
import 'config.dart';
import 'context/runtime_context.dart';
import 'environment.dart';
import 'event.dart';
import 'logger.dart';
import 'protocol/exception_payload_builder.dart';
import 'severity.dart';
import 'transport/event_queue.dart';
import 'transport/http_transport.dart';
import 'transport/transport.dart';
import 'integration/zone_integration.dart';

/// Capture-time processor for per-request tags/extra enrichment.
typedef EventProcessor = Map<String, Object?> Function(
  Map<String, Object?> bag,
);

/// Talaria capture client — enqueues events for batch ingest.
class TalariaClient {
  TalariaClient(
    TalariaOptions options, {
    Transport? transport,
    EventQueue? queue,
    void Function(Object error, [StackTrace? stack])? onTransportError,
  })  : _options = options,
        _sessionId = RuntimeContext.newSessionId(),
        _globalTags = Map<String, String>.from(options.tags),
        _globalUserId = options.userId,
        _minLevel = options.minLevel,
        _enforceDefaultLevel = options.enforceDefaultLevel,
        _loggers = Map<String, LoggerPreset>.from(options.loggers),
        _beforeSend = options.beforeSend {
    final httpTransport = transport is HttpTransport
        ? transport
        : (transport == null
            ? HttpTransport(
                baseUrl: options.baseUrl,
                apiKey: options.apiKey,
                timeout: Duration(
                  milliseconds: (options.httpTimeoutSeconds * 1000).round(),
                ),
              )
            : null);

    _ownedHttp = httpTransport;
    final resolvedTransport = transport ?? httpTransport!;

    _queue = queue ??
        EventQueue(
          transport: resolvedTransport,
          maxBatchSize: options.maxBatchSize,
          flushIntervalMs: options.flushIntervalMs,
          onError: (e) {
            onTransportError?.call(e);
            developer.log('[Talaria] ${e.message}', name: 'talaria');
          },
        );

    if (options.flushIntervalMs > 0) {
      _flushTimer = Timer.periodic(
        Duration(milliseconds: options.flushIntervalMs),
        (_) {
          // ignore: discarded_futures
          flush();
        },
      );
    }

    if (options.defaultIntegrations) {
      _zoneIntegration = ZoneIntegration()..register();
    }
  }

  final TalariaOptions _options;
  late final EventQueue _queue;
  HttpTransport? _ownedHttp;
  final String _sessionId;
  bool _closed = false;

  SeverityLevel _minLevel;
  bool _enforceDefaultLevel;
  final Map<String, LoggerPreset> _loggers;
  final BeforeSendCallback? _beforeSend;

  Map<String, String> _globalTags;
  Map<String, Object?> _globalExtra = {};
  String? _globalUserId;
  final List<EventProcessor> _processors = [];

  ZoneIntegration? _zoneIntegration;
  Timer? _flushTimer;

  /// Optional override for platform wire field (Flutter sets `flutter`).
  String? platformOverride;

  TalariaOptions get options => _options;

  SeverityLevel getMinLevel() => _minLevel;

  void setMinLevel(Object level) {
    _minLevel = SeverityLevel.tryFromMixed(level) ?? _minLevel;
  }

  bool isEnforceDefaultLevel() => _enforceDefaultLevel;

  void setEnforceDefaultLevel(bool enforce) {
    _enforceDefaultLevel = enforce;
  }

  bool isLevelEnabled(Object level) {
    final severity = SeverityLevel.tryFromMixed(level) ?? SeverityLevel.info;
    return severity.atLeast(_minLevel);
  }

  TalariaLogger logger({
    String? name,
    Map<String, String>? tags,
    SeverityLevel? minLevel,
  }) {
    return TalariaLogger(
      this,
      resolveLoggerOptions(name: name, tags: tags, minLevel: minLevel),
    );
  }

  LoggerOptions resolveLoggerOptions({
    String? name,
    Map<String, String>? tags,
    SeverityLevel? minLevel,
  }) {
    final preset = name != null ? _loggers[name] : null;
    final mergedTags = <String, String>{
      ...?preset?.tags,
      ...?tags,
    };
    final resolvedMin = minLevel ?? preset?.minLevel;
    return LoggerOptions(
      name: name,
      tags: mergedTags.isEmpty ? null : mergedTags,
      minLevel: resolvedMin,
    );
  }

  TalariaLogger withTags(Map<String, String> tags) => logger(tags: tags);

  Future<void> debug(String message, {CaptureContext? context}) =>
      captureMessage(message, level: SeverityLevel.debug, context: context);

  Future<void> info(String message, {CaptureContext? context}) =>
      captureMessage(message, level: SeverityLevel.info, context: context);

  Future<void> warning(String message, {CaptureContext? context}) =>
      captureMessage(message, level: SeverityLevel.warning, context: context);

  Future<void> warn(String message, {CaptureContext? context}) =>
      warning(message, context: context);

  Future<void> error(String message, {CaptureContext? context}) =>
      captureMessage(message, level: SeverityLevel.error, context: context);

  Future<void> fatal(String message, {CaptureContext? context}) =>
      captureMessage(message, level: SeverityLevel.fatal, context: context);

  Future<void> log(
    Object level,
    String message, {
    CaptureContext? context,
  }) =>
      captureMessage(message, level: level, context: context);

  Future<void> captureException(
    Object error, {
    StackTrace? stackTrace,
    CaptureContext? context,
  }) =>
      _captureExceptionInternal(
        error,
        stackTrace: stackTrace,
        context: context,
        respectMinLevel: true,
      );

  /// Logger-originated exception capture.
  Future<void> captureExceptionFromLogger(
    Object error, {
    StackTrace? stackTrace,
    CaptureContext? context,
  }) =>
      _captureExceptionInternal(
        error,
        stackTrace: stackTrace,
        context: context,
        respectMinLevel: _enforceDefaultLevel,
      );

  Future<void> captureMessage(
    String message, {
    Object level = SeverityLevel.info,
    CaptureContext? context,
  }) =>
      _captureMessageInternal(
        message,
        level: level,
        context: context,
        respectMinLevel: true,
      );

  /// Logger-originated message capture.
  Future<void> captureMessageFromLogger(
    String message, {
    Object level = SeverityLevel.info,
    CaptureContext? context,
  }) =>
      _captureMessageInternal(
        message,
        level: level,
        context: context,
        respectMinLevel: _enforceDefaultLevel,
      );

  void setTags(Map<String, String> tags) {
    _globalTags = {
      ..._globalTags,
      ...TalariaOptions.normalizeTags(tags),
    };
  }

  void addProcessor(EventProcessor processor) {
    _processors.add(processor);
  }

  void setExtra(Map<String, Object?> extra) {
    _globalExtra = {..._globalExtra, ...extra};
  }

  void setUser(String? userId) {
    _globalUserId = (userId != null && userId.isNotEmpty) ? userId : null;
  }

  Future<void> flush() => _queue.flush();

  Future<void> close() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await flush();
    _closed = true;
    _zoneIntegration?.unregister();
    _ownedHttp?.close();
  }

  int queueSize() => _queue.count;

  Future<void> _captureExceptionInternal(
    Object error, {
    StackTrace? stackTrace,
    CaptureContext? context,
    required bool respectMinLevel,
  }) async {
    if (_closed) {
      return;
    }
    if (respectMinLevel && !SeverityLevel.error.atLeast(_minLevel)) {
      return;
    }
    if (!_options.shouldSample()) {
      return;
    }

    final st = stackTrace ?? StackTrace.current;
    final platform = platformOverride ?? _options.platform;
    final exceptionPayload = ExceptionPayloadBuilder.fromError(
      error,
      st,
      mechanism: context?.mechanism,
      framePlatform: platform == 'flutter' ? 'flutter' : 'dart',
    );

    final extra = <String, Object?>{
      ..._globalExtra,
      ...?context?.extra,
    };

    await _enqueueBuilt(
      message: ExceptionPayloadBuilder.messageOf(error).trim().isEmpty
          ? ExceptionPayloadBuilder.typeName(error)
          : ExceptionPayloadBuilder.messageOf(error),
      level: SeverityLevel.error,
      title: context?.title ?? ExceptionPayloadBuilder.shortName(error),
      stackTrace: st.toString(),
      context: CaptureContext(
        tags: context?.tags,
        extra: extra,
        userId: context?.userId,
      ),
      exception: exceptionPayload,
      platform: platform,
      originalContext: context,
    );
  }

  Future<void> _captureMessageInternal(
    String message, {
    required Object level,
    CaptureContext? context,
    required bool respectMinLevel,
  }) async {
    if (_closed) {
      return;
    }

    final severity = SeverityLevel.tryFromMixed(level) ?? SeverityLevel.info;
    if (respectMinLevel && !severity.atLeast(_minLevel)) {
      return;
    }
    if (!_options.shouldSample()) {
      return;
    }

    final extra = <String, Object?>{
      ..._globalExtra,
      ...?context?.extra,
    };

    await _enqueueBuilt(
      message: message,
      level: severity,
      title: context?.title,
      stackTrace: null,
      context: CaptureContext(
        tags: context?.tags,
        extra: extra,
        userId: context?.userId,
      ),
      originalContext: context,
    );
  }

  Future<void> _enqueueBuilt({
    required String message,
    required SeverityLevel level,
    String? title,
    String? stackTrace,
    required CaptureContext context,
    Map<String, Object?>? exception,
    String? platform,
    CaptureContext? originalContext,
  }) async {
    final runtime = RuntimeContext.collect(
      runtime: (platformOverride ?? _options.platform) == 'flutter'
          ? 'dart'
          : 'dart',
    );
    final runtimeTags = TalariaOptions.normalizeTags(
      Map<String, Object?>.from(runtime['tags'] as Map? ?? const {}),
    );
    final runtimeExtra =
        Map<String, Object?>.from(runtime['extra'] as Map? ?? const {});

    var tags = <String, String>{
      ...runtimeTags,
      ..._globalTags,
    };
    var extra = <String, Object?>{
      ...runtimeExtra,
      ...?context.extra,
    };

    var bag = <String, Object?>{
      'tags': tags,
      'extra': extra,
    };
    for (final processor in _processors) {
      try {
        final result = processor(bag);
        bag = result;
        final resultTags = result['tags'];
        if (resultTags is Map) {
          tags = TalariaOptions.normalizeTags(
            Map<String, Object?>.from(resultTags),
          );
        }
        final resultExtra = result['extra'];
        if (resultExtra is Map) {
          extra = Map<String, Object?>.from(resultExtra);
        }
      } catch (e, st) {
        developer.log(
          '[Talaria] processor failed: $e',
          name: 'talaria',
          error: e,
          stackTrace: st,
        );
      }
    }

    tags = {
      ...tags,
      ...?context.tags,
    };

    var userId = context.userId;
    if (userId == null || userId.isEmpty) {
      userId = _globalUserId;
    }

    var outMessage = message;
    var outLevel = level;
    var outTitle = title;
    var outTags = tags;
    var outExtra = extra;
    var outUserId = userId;
    var outException = exception;

    final beforeSend = _beforeSend;
    if (beforeSend != null) {
      try {
        final eventBag = BeforeSendEvent(
          message: outMessage,
          level: outLevel,
          title: outTitle,
          tags: outTags,
          extra: outExtra,
          userId: outUserId,
          exception: outException,
        );
        final result = beforeSend(
          eventBag,
          BeforeSendHint(
            originalContext: originalContext,
            isException: exception != null,
          ),
        );
        if (result == null) {
          return;
        }
        outMessage = result.message;
        outLevel = result.level;
        outTitle = result.title;
        outTags = result.tags;
        outExtra = result.extra;
        outUserId = result.userId;
        outException = result.exception;
      } catch (e, st) {
        developer.log(
          '[Talaria] beforeSend failed: $e',
          name: 'talaria',
          error: e,
          stackTrace: st,
        );
        return;
      }
    }

    final event = Event(
      message: outMessage,
      environment: Environment.fromMixed(_options.environment),
      level: outLevel,
      eventType: outLevel.toEventType(),
      title: outTitle,
      stackTrace: stackTrace,
      release: _options.release,
      commitSha: _options.commitSha,
      userId: outUserId,
      sessionId: _sessionId,
      requestId: runtime['requestId'] as String?,
      url: runtime['url'] as String?,
      tags: outTags.isEmpty ? null : outTags,
      extraJson: RuntimeContext.encodeExtraJson(outExtra),
      timestamp: RuntimeContext.isoTimestamp(),
      exception: outException,
      platform: platform ?? platformOverride ?? _options.platform,
    );

    _queue.enqueue(event);
  }
}
