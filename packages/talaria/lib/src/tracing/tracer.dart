import 'dart:math';

import '../config.dart';
import '../context/runtime_context.dart';
import '../environment.dart';
import 'span.dart';
import 'trace_context.dart';

/// Snapshot of client fields copied onto finished spans.
class SpanEnrichment {
  const SpanEnrichment({
    required this.environment,
    this.release,
    this.userId,
    this.sessionId,
    this.requestId,
    this.resource = const {},
  });

  final Environment environment;
  final String? release;
  final String? userId;
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

  final TalariaOptions _options;
  final void Function(FinishedSpan span) _enqueue;
  final SpanEnrichment Function() _enrichment;
  final Random _random;

  final List<_RecordingSpan> _stack = [];
  final Map<String, _TraceState> _traces = {};

  Span? get currentSpan {
    for (var i = _stack.length - 1; i >= 0; i--) {
      final span = _stack[i];
      if (!span._finished) {
        return span;
      }
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
    _stack.add(span);
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
    if (state.spanCount >= maxSpansPerTrace) {
      return const NoOpSpan();
    }
    state.spanCount++;
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
    _stack.add(span);
    return span;
  }

  void markErrorInScope({String? message}) {
    final span = currentSpan;
    if (span is _RecordingSpan) {
      span.markError(message: message);
    }
  }

  void finishAll() {
    final open = List<_RecordingSpan>.from(_stack.reversed);
    for (final span in open) {
      if (!span._finished) {
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
    _stack.remove(span);
    final state = _traces[span.traceId];
    if (state == null) {
      return;
    }
    if (span._status == SpanStatus.error) {
      state.forceSampled = true;
    }
    final finished = span._toFinished(_enrichment());
    final shouldSend = state.sampled || state.forceSampled;
    if (shouldSend) {
      _enqueue(finished);
      if (state.held.isNotEmpty) {
        for (final held in state.held) {
          _enqueue(held);
        }
        state.held.clear();
      }
    } else {
      state.held.add(finished);
    }
    if (span.parentSpanId == null || span.parentSpanId!.isEmpty) {
      if (!shouldSend) {
        state.held.clear();
      }
      _traces.remove(span.traceId);
    }
  }
}

class _TraceState {
  _TraceState({required this.sampled});

  bool sampled;
  bool forceSampled = false;
  int spanCount = 0;
  final List<FinishedSpan> held = [];
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
  DateTime? _endTime;

  @override
  bool get isRecording => !_finished;

  @override
  bool get sampled {
    final state = _tracer._traces[traceId];
    return state != null && (state.sampled || state.forceSampled);
  }

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
      environment: enrichment.environment,
      release: enrichment.release,
      userId: enrichment.userId,
      sessionId: enrichment.sessionId,
      requestId: enrichment.requestId ?? RuntimeContext.requestId,
    );
  }
}
