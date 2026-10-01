import 'dart:async';
import 'dart:math';

import '../config.dart';
import '../context/runtime_context.dart';
import 'span.dart';
import 'span_scope.dart';
import 'trace_context.dart';

/// Snapshot of client fields copied onto finished spans.
class SpanEnrichment {
  const SpanEnrichment({
    this.release,
    this.userId,
    this.anonymousId,
    this.sessionId,
    this.requestId,
    this.resource = const {},
  });

  final String? release;
  final String? userId;
  final String? anonymousId;
  final String? sessionId;
  final String? requestId;
  final Map<String, String> resource;
}

/// Head-based tracer. Disabled until [TalariaOptions.isTracingEnabled].
class Tracer {
  Tracer({
    required TalariaOptions options,
    required void Function(FinishedSpan span) enqueue,
    required SpanEnrichment Function() enrichment,
    Random? random,
  })  : _options = options,
        _enqueue = enqueue,
        _enrichment = enrichment,
        _random = random ?? Random();

  static const int maxSpansPerTrace = 200;
  static const int maxSqlSpans = 168;
  static const int reservedNonSql = 32;
  static const double slowQueryMs = 200;
  static const Object _querySpanZoneKey = #talariaRecordQuerySpans;

  final TalariaOptions _options;
  final void Function(FinishedSpan span) _enqueue;
  final SpanEnrichment Function() _enrichment;
  final Random _random;

  final List<Span> _stack = [];
  final Map<String, _TraceState> _traces = {};
  bool _recordQuerySpans = true;

  bool get recordQuerySpans {
    final zoned = Zone.current[_querySpanZoneKey];
    if (zoned is bool) return zoned;
    return _recordQuerySpans;
  }

  void setRecordQuerySpans(bool record) {
    _recordQuerySpans = record;
  }

  /// Automatic SQL spans stay off for the body, including when it throws.
  T withoutQuerySpans<T>(T Function() body) {
    return runZoned(body, zoneValues: {_querySpanZoneKey: false});
  }

  List<Span> get _activeStack => SpanScope.zoneStack() ?? _stack;

  Span? get currentSpan {
    final stack = _activeStack;
    for (var i = stack.length - 1; i >= 0; i--) {
      final span = stack[i];
      if (span.isRecording) {
        return span;
      }
    }
    final sessionId = SpanScope.currentSessionId;
    if (sessionId != null) {
      return SpanScope.forSession(sessionId);
    }
    return null;
  }

  bool get isEnabled => _options.isTracingEnabled;

  /// Start a root transaction. No-op when tracing is off.
  Span startTransaction(
    String name, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?>? attributes,
    Traceparent? parent,
  }) {
    if (!isEnabled) {
      return const NoOpSpan();
    }
    final sampled = _sampleSuccess();
    final traceId = parent?.traceId ?? Traceparent.newTraceId();
    final spanId = Traceparent.newSpanId();
    final state = _TraceState(sampled: sampled || (parent?.sampled ?? false));
    _traces[traceId] = state;
    final span = _RecordingSpan(
      tracer: this,
      traceId: traceId,
      spanId: spanId,
      parentSpanId: parent?.spanId,
      name: name,
      kind: kind,
      startTime: DateTime.now().toUtc(),
    );
    if (attributes != null) {
      span.setAttributes(attributes);
    }
    state.spanCount = 1;
    _activeStack.add(span);
    return span;
  }

  /// Start a child span (or a new root if none is current).
  Span startSpan(
    String name, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?>? attributes,
    Span? parent,
  }) {
    if (!isEnabled) {
      return const NoOpSpan();
    }
    final resolvedParent = parent ?? currentSpan;
    if (resolvedParent == null || !resolvedParent.isRecording) {
      return startTransaction(name, kind: kind, attributes: attributes);
    }
    final state = _traces[resolvedParent.traceId];
    if (state == null) {
      return startTransaction(name, kind: kind, attributes: attributes);
    }
    final queryText = attributes?['db.query.text']?.toString();
    final isQuery = queryText != null && queryText.isNotEmpty;
    if (isQuery && !recordQuerySpans) {
      return const NoOpSpan();
    }
    if (!isQuery && state.spanCount >= maxSpansPerTrace) {
      state.droppedCount++;
      return const NoOpSpan();
    }
    if (!isQuery) {
      state.spanCount++;
    }
    final span = _RecordingSpan(
      tracer: this,
      traceId: resolvedParent.traceId,
      spanId: Traceparent.newSpanId(),
      parentSpanId: resolvedParent.spanId,
      name: name,
      kind: kind,
      startTime: DateTime.now().toUtc(),
    );
    if (attributes != null) {
      span.setAttributes(attributes);
    }
    if (isQuery) {
      span._pendingQuery = true;
    }
    _activeStack.add(span);
    return span;
  }

  void markErrorInScope({String? message}) {
    final span = currentSpan;
    if (span is _RecordingSpan) {
      span.markError(message: message);
    }
  }

  void finishAll() {
    final open = List<Span>.from(_activeStack.reversed);
    for (final span in open) {
      if (span.isRecording) {
        span.finish();
      }
    }
  }

  bool _sampleSuccess() {
    final rate = _options.effectiveTracesSampleRate;
    if (rate >= 1.0) {
      return true;
    }
    if (rate <= 0.0) {
      return false;
    }
    return _random.nextDouble() <= rate;
  }

  void _onFinish(_RecordingSpan span) {
    _activeStack.remove(span);
    final state = _traces[span.traceId];
    if (state == null) {
      return;
    }
    if (span._status == SpanStatus.error) {
      state.forceSampled = true;
    }
    final shouldSend = state.sampled || state.forceSampled;
    final isRoot = span.parentSpanId == null || span.parentSpanId!.isEmpty;

    if (span._pendingQuery && !isRoot) {
      if (_absorbQuery(state, span)) {
        return;
      }
      if (!_canAdmitSql(state)) {
        state.droppedCount++;
        return;
      }
      state.spanCount++;
      state.sqlCount++;
      final finished = span._toFinished(_enrichment());
      final text = span.getAttribute('db.query.text') ?? '';
      final slow = _durationMs(span) >= slowQueryMs;
      final failed = span._status == SpanStatus.error;
      if (!failed && !slow && text.isNotEmpty) {
        final key = '${span.parentSpanId ?? ''}\u0000$text';
        state.queryGroups[key] = finished;
        state.pendingQueryGroups.add(finished);
      } else {
        _keep(state, finished, shouldSend);
      }
      if (shouldSend) {
        _releaseHeld(state);
      }
      return;
    }

    final finished = span._toFinished(_enrichment());
    if (isRoot && state.droppedCount > 0) {
      finished.attributes['dropped_span_count'] = '${state.droppedCount}';
    }
    if (isRoot && shouldSend) {
      _releaseHeld(state);
      for (final pending in state.pendingQueryGroups) {
        _enqueue(pending);
      }
      state.pendingQueryGroups.clear();
    }
    _keep(state, finished, shouldSend);
    if (isRoot) {
      if (!shouldSend) {
        state.held.clear();
        state.pendingQueryGroups.clear();
      }
      _recordQuerySpans = true;
      _traces.remove(span.traceId);
    }
  }

  bool _absorbQuery(_TraceState state, _RecordingSpan span) {
    final text = span.getAttribute('db.query.text') ?? '';
    if (text.isEmpty || span._status == SpanStatus.error) {
      return false;
    }
    final duration = _durationMs(span);
    if (duration >= slowQueryMs) {
      return false;
    }
    final key = '${span.parentSpanId ?? ''}\u0000$text';
    final group = state.queryGroups[key];
    if (group == null) {
      return false;
    }
    final updated = group.rollupExecution(
      executionStart: span.startTime,
      executionEnd: span._endTime ?? span.startTime,
      executionMs: duration,
    );
    state.queryGroups[key] = updated;
    final index =
        state.pendingQueryGroups.indexWhere((item) => item.spanId == group.spanId);
    if (index >= 0) {
      state.pendingQueryGroups[index] = updated;
    }
    return true;
  }

  bool _canAdmitSql(_TraceState state) {
    if (state.sqlCount >= maxSqlSpans || state.spanCount >= maxSpansPerTrace) {
      return false;
    }
    final nonSql = state.spanCount - state.sqlCount;
    final reserve = reservedNonSql - nonSql;
    final hold = reserve < 0 ? 0 : reserve;
    return state.spanCount + hold < maxSpansPerTrace;
  }

  void _keep(_TraceState state, FinishedSpan finished, bool shouldSend) {
    if (shouldSend) {
      _releaseHeld(state);
      _enqueue(finished);
    } else {
      state.held.add(finished);
    }
  }

  void _releaseHeld(_TraceState state) {
    if (state.held.isEmpty) return;
    for (final held in state.held) {
      _enqueue(held);
    }
    state.held.clear();
  }

  double _durationMs(_RecordingSpan span) {
    final end = span._endTime ?? span.startTime;
    final ms = end.difference(span.startTime).inMicroseconds / 1000.0;
    return ms < 0 ? 0 : ms;
  }
}

class _TraceState {
  _TraceState({required this.sampled});

  bool sampled;
  bool forceSampled = false;
  int spanCount = 0;
  int sqlCount = 0;
  int droppedCount = 0;
  final List<FinishedSpan> held = [];
  final List<FinishedSpan> pendingQueryGroups = [];
  final Map<String, FinishedSpan> queryGroups = {};
}

class _RecordingSpan implements Span {
  _RecordingSpan({
    required Tracer tracer,
    required this.traceId,
    required this.spanId,
    required this.parentSpanId,
    required this.name,
    required this.kind,
    required this.startTime,
  }) : _tracer = tracer;

  final Tracer _tracer;

  @override
  final String traceId;

  @override
  final String spanId;

  @override
  final String? parentSpanId;

  @override
  final String name;

  @override
  final SpanKind kind;

  final DateTime startTime;
  final Map<String, String> _attributes = {};
  final List<SpanEvent> _events = [];
  final List<SpanLink> _links = [];

  SpanStatus _status = SpanStatus.unset;
  String? _statusMessage;
  bool _finished = false;
  bool _pendingQuery = false;
  DateTime? _endTime;

  @override
  bool get isRecording => !_finished;

  @override
  bool get sampled {
    final state = _tracer._traces[traceId];
    return state != null && (state.sampled || state.forceSampled);
  }

  @override
  SpanStatus get status => _status;

  @override
  String? getAttribute(String key) => _attributes[key];

  @override
  void setStatus(SpanStatus status, {String? message}) {
    if (_finished) {
      return;
    }
    _status = status;
    if (message != null) {
      _statusMessage = message;
    }
    if (status == SpanStatus.error) {
      _tracer._traces[traceId]?.forceSampled = true;
    }
  }

  @override
  void setAttribute(String key, Object? value) {
    if (_finished || key.isEmpty || value == null) {
      return;
    }
    if (_attributes.length >= 64 && !_attributes.containsKey(key)) {
      return;
    }
    var text = value.toString();
    if (text.length > 2048) {
      text = text.substring(0, 2048);
    }
    _attributes[key] = text;
  }

  @override
  void setAttributes(Map<String, Object?> attributes) {
    for (final entry in attributes.entries) {
      setAttribute(entry.key, entry.value);
    }
  }

  @override
  void addEvent(String name, {Map<String, String>? attributes}) {
    if (_finished || name.isEmpty) {
      return;
    }
    _events.add(SpanEvent(name: name, attributes: attributes));
  }

  @override
  void addLink(SpanLink link) {
    if (_finished) {
      return;
    }
    _links.add(link);
  }

  @override
  void markError({String? message}) {
    setStatus(SpanStatus.error, message: message);
  }

  @override
  void finish({
    DateTime? endTime,
    SpanStatus? status,
    String? statusMessage,
  }) {
    if (_finished) {
      return;
    }
    if (status != null) {
      setStatus(status, message: statusMessage);
    }
    _finished = true;
    var end = (endTime ?? DateTime.now()).toUtc();
    if (end.isBefore(startTime)) {
      end = startTime;
    }
    _endTime = end;
    _tracer._onFinish(this);
  }

  @override
  Traceparent toTraceparent() => Traceparent(
        traceId: traceId,
        spanId: spanId,
        sampled: sampled,
      );

  FinishedSpan _toFinished(SpanEnrichment enrichment) {
    return FinishedSpan(
      traceId: traceId,
      spanId: spanId,
      parentSpanId: parentSpanId,
      name: name,
      kind: kind,
      startTime: startTime,
      endTime: _endTime ?? DateTime.now().toUtc(),
      status: _status,
      statusMessage: _statusMessage,
      attributes: Map<String, String>.from(_attributes),
      resource: Map<String, String>.from(enrichment.resource),
      events: List<SpanEvent>.from(_events),
      links: List<SpanLink>.from(_links),
      release: enrichment.release,
      userId: enrichment.userId ??
          _attributes['enduser.id'] ??
          _attributes['user.id'],
      anonymousId: enrichment.anonymousId,
      sessionId: enrichment.sessionId,
      requestId: enrichment.requestId ?? RuntimeContext.requestId,
    );
  }
}
