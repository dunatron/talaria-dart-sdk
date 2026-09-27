import 'dart:async';
import 'dart:developer' as developer;

import 'analytics/analytics.dart';
import 'capture_context.dart';
import 'config.dart';
import 'event_filters.dart';
import 'context/runtime_context.dart';
import 'environment.dart';
import 'event.dart';
import 'identity/identity.dart';
import 'identity/storage.dart';
import 'logger.dart';
import 'protocol/exception_payload_builder.dart';
import 'severity.dart';
import 'tracing/breadcrumbs.dart';
import 'tracing/span.dart';
import 'tracing/span_scope.dart';
import 'tracing/tracer.dart';
import 'tracing/trace_context.dart';
import 'transport/analytics_queue.dart';
import 'transport/discards.dart';
import 'transport/event_queue.dart';
import 'transport/http_transport.dart';
import 'transport/ingest_error.dart';
import 'transport/span_queue.dart';
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
    DateTime Function()? clock,
    TalariaStorage? storage,
  })  : _options = options,
        _identity = Identity(
          storage: storage ?? options.storage,
          clock: clock,
        ),
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
    _discardTransport = resolvedTransport;

    _queue = queue ??
        EventQueue(
          transport: resolvedTransport,
          maxBatchSize: options.maxBatchSize,
          flushIntervalMs: options.flushIntervalMs,
          onError: (e) {
            _handleTransportError(e, IngestSignal.events);
            onTransportError?.call(e);
            developer.log('[Talaria] ${e.message}', name: 'talaria');
          },
          onDiscard: (count, reason) => _recordDiscard(
            DiscardSignal.events,
            reason,
            count,
          ),
        );

    _spanQueue = SpanQueue(
      transport: resolvedTransport,
      maxBatchSize: options.maxBatchSize,
      flushIntervalMs: options.flushIntervalMs,
      onError: (e) {
        _handleTransportError(e, IngestSignal.spans);
        onTransportError?.call(e);
        developer.log('[Talaria] ${e.message}', name: 'talaria');
      },
      onDiscard: (count, reason) => _recordDiscard(
        DiscardSignal.spans,
        reason,
        count,
      ),
    );

    _analyticsQueue = AnalyticsQueue(
      transport: resolvedTransport,
      maxBatchSize: options.maxBatchSize,
      flushIntervalMs: options.flushIntervalMs,
      onError: (e) {
        _handleTransportError(e, IngestSignal.analytics);
        onTransportError?.call(e);
        developer.log('[Talaria] ${e.message}', name: 'talaria');
      },
      onDiscard: (count, reason) => _recordDiscard(
        DiscardSignal.analytics,
        reason,
        count,
      ),
    );

    analytics = TalariaAnalytics(
      identity: _identity,
      queue: _analyticsQueue,
      enabled: options.enableAnalytics,
      isDisabled: () => _analyticsDisabled || _options.analyticsPaused,
      isClosed: () => _closed,
      isFlutter: () =>
          platformOverride == 'flutter' || _options.platform == 'flutter',
      platform: () => platformOverride ?? _options.platform,
      environment: () => _options.environment.wireValue,
      release: () => _options.release,
      userId: () => _globalUserId,
      setUser: setUser,
      currentSpan: _spanForCapture,
      requestId: () => currentRequestId,
      onDiscard: (reason) => _recordDiscard(DiscardSignal.analytics, reason),
    );

    tracer = Tracer(
      options: options,
      enqueue: (span) {
        if (_spansDisabled || _options.transactionsPaused) {
          _recordDiscard(DiscardSignal.spans, DiscardReason.signalDisabled);
          return;
        }
        _spanQueue.enqueue(span);
      },
      enrichment: _spanEnrichment,
    );

    if (httpTransport != null) {
      unawaited(_bootstrapPolicy(httpTransport));
    }

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
    _screenTransport = resolvedTransport;
  }

  final TalariaOptions _options;
  late final EventQueue _queue;
  late final SpanQueue _spanQueue;
  late final AnalyticsQueue _analyticsQueue;
  late final Tracer tracer;
  late final TalariaAnalytics analytics;
  final Identity _identity;
  final BreadcrumbBuffer _breadcrumbs = BreadcrumbBuffer();
  HttpTransport? _ownedHttp;
  Transport? _screenTransport;
  bool _closed = false;
  bool _eventsDisabled = false;
  bool _spansDisabled = false;
  bool _analyticsDisabled = false;
  bool _loggedIngestDisable = false;

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
  Timer? _policyTimer;
  Transport? _discardTransport;
  final DiscardBuffer _discards = DiscardBuffer();

  /// Optional override for platform wire field (Flutter sets `flutter`).
  String? platformOverride;

  /// `enduser.id` / `user.id` on the current span when no global user is set.
  static String? userIdFromSpan(Span? span) {
    if (span == null || !span.isRecording) {
      return null;
    }
    final id = span.getAttribute('enduser.id') ?? span.getAttribute('user.id');
    if (id == null || id.isEmpty) {
      return null;
    }
    return id;
  }

  TalariaOptions get options => _options;

  /// User id from [setUser], falling back to the id in options.
  String? get userId => _globalUserId;

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

  void addBreadcrumb(Breadcrumb breadcrumb) {
    final scoped = BreadcrumbScope.current();
    if (scoped != null) {
      scoped.add(breadcrumb);
      return;
    }
    _breadcrumbs.add(breadcrumb);
  }

  /// True after a permanent ingest auth error (`retry: false` / invalid key).
  bool get isIngestDisabled =>
      _eventsDisabled && _spansDisabled && _analyticsDisabled;

  bool get isEventsIngestDisabled => _eventsDisabled;

  bool get isSpansIngestDisabled => _spansDisabled;

  bool get isAnalyticsIngestDisabled => _analyticsDisabled;

  bool get isClosed => _closed;

  /// Durable visitor id (persisted when [TalariaStorage] is durable).
  String get anonymousId => _identity.anonymousId;

  /// Current session id (rotates after 30 minutes idle or midnight UTC).
  String get sessionId => _identity.sessionId;

  Span startTransaction(
    String name, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?>? attributes,
    Traceparent? parent,
  }) {
    return tracer.startTransaction(
      name,
      kind: kind,
      attributes: attributes,
      parent: parent,
    );
  }

  Span startSpan(
    String name, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?>? attributes,
    Span? parent,
  }) {
    return tracer.startSpan(
      name,
      kind: kind,
      attributes: attributes,
      parent: parent,
    );
  }

  /// W3C `traceparent` for the active span, or null when tracing is off / idle.
  String? getTraceparent() {
    final span = tracer.currentSpan;
    if (span == null || !span.isRecording) {
      return null;
    }
    if (span.traceId == '0' * 32 || span.spanId == '0' * 16) {
      return null;
    }
    return Traceparent(
      traceId: span.traceId,
      spanId: span.spanId,
      sampled: span.sampled,
    ).toHeader();
  }

  String? get currentRequestId {
    final fromRuntime = RuntimeContext.requestId;
    if (fromRuntime != null && fromRuntime.isNotEmpty) {
      return fromRuntime;
    }
    final span = tracer.currentSpan;
    if (span != null && span.isRecording) {
      return span.spanId;
    }
    return null;
  }

  void setExtra(Map<String, Object?> extra) {
    _globalExtra = {..._globalExtra, ...extra};
  }

  void setUser(String? userId) {
    _globalUserId = (userId != null && userId.isNotEmpty) ? userId : null;
  }

  /// Flutter screen heatmap ingest. No-op until a transport implements it.
  Future<Map<String, Object?>> sendScreenHeatmapBatch(
    List<Map<String, Object?>> screenViews,
  ) {
    final transport = _screenTransport;
    if (transport == null || screenViews.isEmpty) return Future.value(const {});
    return transport.sendScreenHeatmapBatch(screenViews);
  }

  Future<void> uploadScreenHeatmapSnapshot(Map<String, Object?> input) {
    final transport = _screenTransport;
    if (transport == null) return Future.value();
    return transport.uploadScreenHeatmapSnapshot(input);
  }

  Future<void> uploadScreenHeatmapRecording(Map<String, Object?> input) {
    final transport = _screenTransport;
    if (transport == null) return Future.value();
    return transport.uploadScreenHeatmapRecording(input);
  }

  final List<Future<void> Function()> _beforeFlush = [];

  /// Runs before the queues drain. Flutter screen heatmaps register here.
  void addBeforeFlush(Future<void> Function() hook) {
    _beforeFlush.add(hook);
  }

  void removeBeforeFlush(Future<void> Function() hook) {
    _beforeFlush.remove(hook);
  }

  Future<void> flush() async {
    for (final hook in List<Future<void> Function()>.from(_beforeFlush)) {
      await hook();
    }
    await _queue.flush();
    await _spanQueue.flush();
    await _analyticsQueue.flush();
    await _flushDiscards();
  }

  Future<void> close() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _policyTimer?.cancel();
    _policyTimer = null;
    tracer.finishAll();
    await flush();
    _closed = true;
    _zoneIntegration?.unregister();
    _ownedHttp?.close();
  }

  int queueSize() => _queue.count;

  Span? _spanForCapture() {
    final sessionId = SpanScope.currentSessionId;
    if (sessionId != null) {
      final bound = SpanScope.forSession(sessionId);
      if (bound != null && bound.isRecording) {
        return bound;
      }
    }
    return tracer.currentSpan;
  }

  static final Map<String, ({int fetchedAt, Map<String, Object?> document})>
      _policyCache = {};

  /// Test-only. Policy cache is process-wide so tests do not share documents.
  static void clearPolicyCache() => _policyCache.clear();

  Future<void> _bootstrapPolicy(HttpTransport transport) async {
    final key = _options.apiKey.hashCode.toRadixString(16);
    final cached = _policyCache[key];
    final now = DateTime.now().millisecondsSinceEpoch;
    if (cached != null) {
      _applyPolicyDocument(cached.document);
      final ttlMs = _ttlMs(cached.document);
      if (now - cached.fetchedAt < ttlMs) {
        _schedulePolicyRefresh(transport, ttlMs - (now - cached.fetchedAt));
        return;
      }
    }
    await _refreshPolicy(transport);
  }

  Future<void> _refreshPolicy(HttpTransport transport) async {
    if (_closed) {
      return;
    }
    final key = _options.apiKey.hashCode.toRadixString(16);
    final cached = _policyCache[key];
    try {
      final document = await transport.fetchSdkConfig(
        revision: cached?.document['revision'] as String?,
        platform: platformOverride ?? _options.platform,
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      if (document['unchanged'] == true && cached != null) {
        _policyCache[key] = (fetchedAt: now, document: cached.document);
        _schedulePolicyRefresh(transport, _ttlMs(cached.document));
        return;
      }
      _applyPolicyDocument(document);
      _policyCache[key] = (fetchedAt: now, document: document);
      _schedulePolicyRefresh(transport, _ttlMs(document));
    } catch (_) {
      _schedulePolicyRefresh(transport, 60 * 1000);
    }
  }

  void _applyPolicyDocument(Map<String, Object?> document) {
    _options.applySdkDocument(document);
    if (_options.enableAnalytics) {
      analytics.optIn();
    } else {
      analytics.optOut();
    }
  }

  void _schedulePolicyRefresh(HttpTransport transport, int delayMs) {
    _policyTimer?.cancel();
    if (_closed) {
      return;
    }
    final wait = delayMs.clamp(60 * 1000, 60 * 60 * 1000);
    _policyTimer = Timer(Duration(milliseconds: wait), () {
      unawaited(_refreshPolicy(transport));
    });
  }

  static int _ttlMs(Map<String, Object?> document) {
    return (((document['ttlSeconds'] as num?)?.toInt() ?? 300).clamp(60, 3600)) *
        1000;
  }

  void _recordDiscard(String signal, String reason, [int count = 1]) {
    if (_closed || isIngestDisabled) {
      return;
    }
    _discards.record(signal: signal, reason: reason, count: count);
  }

  Future<void> _flushDiscards() async {
    final rows = _discards.drain();
    if (rows.isEmpty || isIngestDisabled) {
      return;
    }
    final transport = _discardTransport;
    if (transport == null) {
      return;
    }
    try {
      await transport.reportDiscards(rows);
    } catch (_) {
      for (final row in rows) {
        _discards.record(
          signal: row.signal,
          reason: row.reason,
          count: row.count,
        );
      }
    }
  }

  void _handleTransportError(TransportException error, IngestSignal signal) {
    final parsed = IngestError(
      className: error.className,
      message: error.bodyMessage ?? error.message,
      retry: error.retry,
    );
    if (!parsed.isPermanent) {
      return;
    }
    final signalOff = parsed.disabledSignal;
    if (signalOff == 'spans') {
      _spansDisabled = true;
      return;
    }
    if (signalOff == 'analytics') {
      _analyticsDisabled = true;
      return;
    }
    if (signalOff == 'events') {
      _eventsDisabled = true;
      return;
    }
    if (parsed.isScopeOnly) {
      switch (signal) {
        case IngestSignal.events:
          _eventsDisabled = true;
        case IngestSignal.spans:
          _spansDisabled = true;
        case IngestSignal.replay:
          _eventsDisabled = true;
          _spansDisabled = true;
        case IngestSignal.analytics:
          _analyticsDisabled = true;
      }
    } else {
      _eventsDisabled = true;
      _spansDisabled = true;
      _analyticsDisabled = true;
    }
    if (!_loggedIngestDisable) {
      _loggedIngestDisable = true;
      developer.log(
        '[Talaria] ingest disabled after permanent client error: ${error.message}',
        name: 'talaria',
      );
    }
  }

  Future<void> _captureExceptionInternal(
    Object error, {
    StackTrace? stackTrace,
    CaptureContext? context,
    required bool respectMinLevel,
  }) async {
    if (_closed) {
      return;
    }
    if (_eventsDisabled || _options.eventsPaused) {
      _recordDiscard(DiscardSignal.events, DiscardReason.signalDisabled);
      return;
    }
    if (respectMinLevel && !SeverityLevel.error.atLeast(_minLevel)) {
      return;
    }
    if (shouldDropEvent(
      message: ExceptionPayloadBuilder.messageOf(error),
      stackTrace: (stackTrace ?? StackTrace.current).toString(),
      ignoreErrors: _options.ignoreErrors,
      ignoreUrls: _options.ignoreUrls,
    )) {
      return;
    }
    if (!_options.shouldSample()) {
      _recordDiscard(DiscardSignal.events, DiscardReason.sampleRate);
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
    if (_eventsDisabled || _options.eventsPaused) {
      _recordDiscard(DiscardSignal.events, DiscardReason.signalDisabled);
      return;
    }

    final severity = SeverityLevel.tryFromMixed(level) ?? SeverityLevel.info;
    if (respectMinLevel && !severity.atLeast(_minLevel)) {
      return;
    }
    if (shouldDropEvent(
      message: message,
      ignoreErrors: _options.ignoreErrors,
      ignoreUrls: _options.ignoreUrls,
    )) {
      return;
    }
    if (!_options.shouldSample()) {
      _recordDiscard(DiscardSignal.events, DiscardReason.sampleRate);
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
    if (_eventsDisabled || _options.eventsPaused) {
      _recordDiscard(DiscardSignal.events, DiscardReason.signalDisabled);
      return;
    }
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
    var url = runtime['url'] as String?;
    var requestId = runtime['requestId'] as String?;

    var bag = <String, Object?>{
      'tags': tags,
      'extra': extra,
      'url': url,
      'requestId': requestId,
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
        final resultUrl = result['url'];
        if (resultUrl is String) {
          url = resultUrl.isEmpty ? null : resultUrl;
        }
        final resultRequestId = result['requestId'];
        if (resultRequestId is String) {
          requestId = resultRequestId.isEmpty ? null : resultRequestId;
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
      userId = RuntimeContext.userId ??
          _globalUserId ??
          userIdFromSpan(_spanForCapture());
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

    final isError = outException != null ||
        outLevel == SeverityLevel.error ||
        outLevel == SeverityLevel.fatal;

    String? traceId;
    String? spanId;
    List<Map<String, Object?>>? breadcrumbs;
    if (isError) {
      tracer.markErrorInScope(message: outMessage);
      final span = _spanForCapture();
      if (span != null && span.isRecording) {
        traceId = span.traceId;
        spanId = span.spanId;
      }
      final trail = (BreadcrumbScope.current() ?? _breadcrumbs).snapshot();
      if (trail.isNotEmpty) {
        breadcrumbs = [for (final b in trail) b.toWire()];
      }
    }

    _identity.touch();
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
      anonymousId: _identity.anonymousId,
      sessionId: _identity.sessionId,
      requestId: requestId,
      url: url,
      tags: outTags.isEmpty ? null : outTags,
      extraJson: RuntimeContext.encodeExtraJson(outExtra),
      timestamp: RuntimeContext.isoTimestamp(),
      exception: outException,
      platform: platform ?? platformOverride ?? _options.platform,
      traceId: traceId,
      spanId: spanId,
      breadcrumbs: breadcrumbs,
      userAgent: RuntimeContext.userAgent,
    );

    _queue.enqueue(event);
  }

  SpanEnrichment _spanEnrichment() {
    final service = _globalTags['service'] ??
        (_options.platform == 'flutter' || platformOverride == 'flutter'
            ? 'flutter'
            : 'dart');
    _identity.touch();
    return SpanEnrichment(
      environment: _options.environment,
      release: _options.release,
      userId: _globalUserId ?? userIdFromSpan(tracer.currentSpan),
      anonymousId: _identity.anonymousId,
      sessionId: _identity.sessionId,
      requestId: currentRequestId,
      resource: {
        'service.name': service,
        if (_options.release != null && _options.release!.isNotEmpty)
          'service.version': _options.release!,
        'deployment.environment': _options.environment.wireValue,
      },
    );
  }
}
