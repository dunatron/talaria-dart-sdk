import 'package:talaria/talaria.dart';

/// Result of [SessionTransaction.bindOrStart].
class SessionBindResult {
  const SessionBindResult({required this.span, required this.created});

  final Span span;
  final bool created;
}

/// Binds or starts a per-session root span without adopting another session.
class SessionTransaction {
  SessionTransaction._();

  static const String genericDiagnosticPrefix =
      'Internal server error. Request handler failed';

  /// Adopt the Relic SERVER span only inside its zone, never for FutureCalls.
  static SessionBindResult bindOrStart({
    required TalariaClient client,
    required String sessionId,
    required String name,
    required SpanKind kind,
    required Map<String, String> attributes,
    required bool isFutureCall,
    String? userId,
  }) {
    final bound = SpanScope.forSession(sessionId);
    if (bound != null) {
      applyUser(bound, userId);
      return SessionBindResult(span: bound, created: false);
    }

    final inRelicZone = SpanScope.zoneStack() != null;
    if (inRelicZone && !isFutureCall) {
      final current = client.tracer.currentSpan;
      if (current != null && current.isRecording) {
        SpanScope.bindSession(sessionId, current);
        applyUser(current, userId);
        return SessionBindResult(span: current, created: false);
      }
    }

    final span = client.startTransaction(
      name,
      kind: kind,
      attributes: attributes,
    );
    SpanScope.bindSession(sessionId, span);
    applyUser(span, userId);
    return SessionBindResult(span: span, created: true);
  }

  static void applyUser(Span span, String? userId) {
    final trimmed = userId?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return;
    }
    span.setAttribute('enduser.id', trimmed);
    span.setAttribute('user.id', trimmed);
  }

  static bool isGenericDiagnosticMessage(String? message) {
    if (message == null || message.isEmpty) {
      return false;
    }
    return message.startsWith(genericDiagnosticPrefix);
  }
}
