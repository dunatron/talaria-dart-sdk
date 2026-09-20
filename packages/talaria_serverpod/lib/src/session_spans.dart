import 'package:serverpod/serverpod.dart';
import 'package:talaria/talaria.dart';

import 'paths.dart';

/// Names and attributes for Serverpod session-rooted spans.
class SessionSpans {
  SessionSpans._();

  static String sessionIdOf(Session session) => session.sessionId.toString();

  static bool shouldSkip(Session session) {
    return TalariaServerpodPaths.shouldSkipSession(
      endpoint: session.endpoint,
      method: session.method,
    );
  }

  static String name(Session session) {
    return nameFor(
      endpoint: session.endpoint,
      method: session.method,
      futureCallName:
          session is FutureCallSession ? session.futureCallName : null,
    );
  }

  static String nameFor({
    required String endpoint,
    String? method,
    String? futureCallName,
  }) {
    if (futureCallName != null && futureCallName.isNotEmpty) {
      return 'FutureCall.$futureCallName';
    }
    if (method != null && method.isNotEmpty) {
      return '$endpoint/$method';
    }
    return endpoint;
  }

  static SpanKind kind(Session session) =>
      kindFor(isFutureCall: session is FutureCallSession);

  static SpanKind kindFor({required bool isFutureCall}) {
    return isFutureCall ? SpanKind.consumer : SpanKind.server;
  }

  static Map<String, String> attributes(Session session) {
    return attributesFor(
      endpoint: session.endpoint,
      method: session.method,
      futureCallName:
          session is FutureCallSession ? session.futureCallName : null,
      isMethodStream: session is MethodStreamSession,
    );
  }

  static Map<String, String> attributesFor({
    required String endpoint,
    String? method,
    String? futureCallName,
    bool isMethodStream = false,
  }) {
    if (futureCallName != null && futureCallName.isNotEmpty) {
      return {
        'serverpod.session.kind': 'futureCall',
        'serverpod.future_call': futureCallName,
      };
    }
    return {
      'serverpod.session.kind': isMethodStream ? 'methodStream' : 'method',
      'http.route': method != null && method.isNotEmpty
          ? '/$endpoint/$method'
          : '/$endpoint',
      if (method != null && method.isNotEmpty) 'serverpod.method': method,
      'serverpod.endpoint': endpoint,
    };
  }
}
