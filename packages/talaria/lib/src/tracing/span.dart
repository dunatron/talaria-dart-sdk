import '../context/runtime_context.dart';
import '../environment.dart';
import 'trace_context.dart';

/// OTel SpanKind wire values (`SpanKindWire`).
enum SpanKind {
  internal,
  server,
  client,
  producer,
  consumer,
}

/// OTel span status wire values (`SpanStatusWire`).
enum SpanStatus {
  unset,
  ok,
  error,
}

/// Optional span event (`SpanEventDto`).
class SpanEvent {
  SpanEvent({
    required this.name,
    DateTime? timestamp,
    this.attributes,
  }) : timestamp = (timestamp ?? DateTime.now()).toUtc();

  final DateTime timestamp;
  final String name;
  final Map<String, String>? attributes;

  Map<String, Object?> toWire() {
    final wire = <String, Object?>{
      '__className__': 'SpanEventDto',
      'timestamp': RuntimeContext.isoTimestamp(timestamp),
      'name': name,
    };
    if (attributes != null && attributes!.isNotEmpty) {
      wire['attributes'] = attributes;
    }
    return wire;
  }
}

/// Optional span link (`SpanLinkDto`).
class SpanLink {
  const SpanLink({required this.traceId, required this.spanId});

  final String traceId;
  final String spanId;

  Map<String, Object?> toWire() => {
        '__className__': 'SpanLinkDto',
        'traceId': traceId,
        'spanId': spanId,
      };
}

/// Timed operation. No-op when tracing is disabled.
abstract class Span {
  String get traceId;
  String get spanId;
  String? get parentSpanId;
  String get name;
  SpanKind get kind;

  /// Local recording (not the head-sample send decision).
  bool get isRecording;

  /// Head-based sample bit (may be upgraded on error).
  bool get sampled;

  void setStatus(SpanStatus status, {String? message});
  void setAttribute(String key, Object? value);
  void setAttributes(Map<String, Object?> attributes);
  void addEvent(String name, {Map<String, String>? attributes});
  void addLink(SpanLink link);

  /// Mark this trace as an error transaction (100% sample).
  void markError({String? message});

  void finish({DateTime? endTime, SpanStatus? status, String? statusMessage});

  Traceparent toTraceparent();
}

/// Finished span ready for `IngestSpanInput`.
class FinishedSpan {
  FinishedSpan({
    required this.traceId,
    required this.spanId,
    this.parentSpanId,
    required this.name,
    required this.kind,
    required this.startTime,
    required this.endTime,
    this.status = SpanStatus.unset,
    this.statusMessage,
    Map<String, String>? attributes,
    Map<String, String>? resource,
    List<SpanEvent>? events,
    List<SpanLink>? links,
    required this.environment,
    this.release,
    this.userId,
    this.sessionId,
    this.requestId,
  })  : attributes = attributes ?? const {},
        resource = resource ?? const {},
        events = events ?? const [],
        links = links ?? const [];

  final String traceId;
  final String spanId;
  final String? parentSpanId;
  final String name;
  final SpanKind kind;
  final DateTime startTime;
  final DateTime endTime;
  final SpanStatus status;
  final String? statusMessage;
  final Map<String, String> attributes;
  final Map<String, String> resource;
  final List<SpanEvent> events;
  final List<SpanLink> links;
  final Environment environment;
  final String? release;
  final String? userId;
  final String? sessionId;
  final String? requestId;

  bool get isRoot => parentSpanId == null || parentSpanId!.isEmpty;

  Map<String, Object?> toWire() {
    final wire = <String, Object?>{
      '__className__': 'IngestSpanInput',
      'traceId': traceId,
      'spanId': spanId,
      'name': name,
      'kind': kind.name,
      'startTime': RuntimeContext.isoTimestamp(startTime),
      'endTime': RuntimeContext.isoTimestamp(endTime),
    };

    void put(String key, Object? value) {
      if (value == null) {
        return;
      }
      if (value is String && value.isEmpty) {
        return;
      }
      if (value is Map && value.isEmpty) {
        return;
      }
      if (value is List && value.isEmpty) {
        return;
      }
      wire[key] = value;
    }

    put('parentSpanId', parentSpanId);
    put('status', status.name);
    put('statusMessage', statusMessage);
    put('attributes', attributes.isEmpty ? null : attributes);
    put('resource', resource.isEmpty ? null : resource);
    put(
      'events',
      events.isEmpty ? null : [for (final e in events) e.toWire()],
    );
    put(
      'links',
      links.isEmpty ? null : [for (final l in links) l.toWire()],
    );
    put('environment', environment.wireValue);
    put('release', release);
    put('userId', userId);
    put('sessionId', sessionId);
    put('requestId', requestId);

    return wire;
  }
}

class NoOpSpan implements Span {
  const NoOpSpan();

  @override
  String get traceId => '0' * 32;

  @override
  String get spanId => '0' * 16;

  @override
  String? get parentSpanId => null;

  @override
  String get name => '';

  @override
  SpanKind get kind => SpanKind.internal;

  @override
  bool get isRecording => false;

  @override
  bool get sampled => false;

  @override
  void setStatus(SpanStatus status, {String? message}) {}

  @override
  void setAttribute(String key, Object? value) {}

  @override
  void setAttributes(Map<String, Object?> attributes) {}

  @override
  void addEvent(String name, {Map<String, String>? attributes}) {}

  @override
  void addLink(SpanLink link) {}

  @override
  void markError({String? message}) {}

  @override
  void finish({
    DateTime? endTime,
    SpanStatus? status,
    String? statusMessage,
  }) {}

  @override
  Traceparent toTraceparent() => Traceparent(
        traceId: traceId,
        spanId: spanId,
        sampled: false,
      );
}
