import 'dart:async';

import 'span.dart';

/// Concurrent-safe current-span scope for multi-session servers.
///
/// [Tracer] uses a Zone-local stack when [run] / [runAsync] is active so
/// overlapping Serverpod sessions do not share a process-wide current span.
/// [bindSession] is a fallback when work is not in that Zone (FutureCalls).
class SpanScope {
  SpanScope._();

  /// Zone value: `List<Span>` isolated current-span stack.
  static const Object stackZoneKey = #talariaSpanStack;

  /// Zone value: optional session id string for this request.
  static const Object sessionIdZoneKey = #talariaSpanSessionId;

  static final Map<String, Span> _sessions = {};

  static void bindSession(String sessionId, Span span) {
    final id = sessionId.trim();
    if (id.isEmpty) {
      return;
    }
    _sessions[id] = span;
  }

  static void unbindSession(String sessionId) {
    _sessions.remove(sessionId.trim());
  }

  static Span? forSession(String sessionId) {
    final id = sessionId.trim();
    if (id.isEmpty) {
      return null;
    }
    final span = _sessions[id];
    if (span == null || !span.isRecording) {
      return null;
    }
    return span;
  }

  /// Session id bound on the current Zone, if any.
  static String? get currentSessionId {
    final fromZone = Zone.current[sessionIdZoneKey];
    if (fromZone is String && fromZone.isNotEmpty) {
      return fromZone;
    }
    return null;
  }

  /// Isolated span stack for this Zone, or null when using the tracer default.
  static List<Span>? zoneStack() {
    final fromZone = Zone.current[stackZoneKey];
    if (fromZone is List<Span>) {
      return fromZone;
    }
    return null;
  }

  /// Run [body] with an isolated current-span stack.
  static T run<T>(T Function() body, {String? sessionId}) {
    return Zone.current.fork(zoneValues: {
      stackZoneKey: <Span>[],
      if (sessionId != null && sessionId.isNotEmpty)
        sessionIdZoneKey: sessionId,
    }).run(body);
  }

  /// Async variant of [run].
  static Future<T> runAsync<T>(
    Future<T> Function() body, {
    String? sessionId,
  }) {
    return Zone.current.fork(zoneValues: {
      stackZoneKey: <Span>[],
      if (sessionId != null && sessionId.isNotEmpty)
        sessionIdZoneKey: sessionId,
    }).run(body);
  }

  /// Test / shutdown helper.
  static void clearSessions() {
    _sessions.clear();
  }
}
