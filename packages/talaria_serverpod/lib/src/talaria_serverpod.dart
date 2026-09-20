import 'package:serverpod/serverpod.dart';
import 'package:talaria/talaria.dart';

import 'relic_middleware.dart';
import 'session_spans.dart';
import 'session_transaction.dart';
import 'tracing_database.dart';

/// Serverpod adapter: Relic SERVER spans, Postgres CLIENT spans, FutureCalls.
class TalariaServerpod {
  TalariaServerpod._();

  static bool _attached = false;

  /// Initialize the shared [Talaria] client for a Serverpod process.
  static Future<TalariaClient> init(
    TalariaOptions options, {
    Transport? transport,
  }) {
    final tags = {
      'runtime': 'serverpod',
      ...options.tags,
    };
    return Talaria.init(
      options.copyWith(
        tags: tags,
        defaultIntegrations: false,
      ),
      transport: transport,
    );
  }

  /// Pass to `Serverpod(..., databaseInterceptor: TalariaServerpod.interceptDatabase)`.
  ///
  /// Safe to register before [init]; no-ops until a client exists and tracing
  /// is enabled. Starts a FutureCall CONSUMER transaction when no HTTP span
  /// is in scope.
  static Database interceptDatabase(Session session, Database inner) {
    final client = Talaria.getClient();
    if (client == null || !client.tracer.isEnabled) {
      return inner;
    }
    if (SessionSpans.shouldSkip(session)) {
      return inner;
    }

    _ensureSessionTransaction(client, session);
    return TracingDatabase(inner, client: client, session: session);
  }

  /// Relic middleware on the API and web servers. Idempotent.
  static void attach(Serverpod pod, {TalariaClient? client}) {
    final resolved = client ?? Talaria.getClient();
    if (resolved == null || _attached) {
      return;
    }
    _attached = true;

    final middleware = talariaRelicMiddleware(resolved);
    pod.server.addMiddleware(middleware);
    try {
      pod.webServer.addMiddleware(middleware, '/');
    } catch (_) {
      // Web server is optional in some Serverpod configs.
    }
  }

  /// Serverpod diagnostic exceptions → Talaria events (with active trace ids).
  static void handleExceptionEvent(ExceptionEvent event) {
    if (SessionTransaction.isGenericDiagnosticMessage(event.message)) {
      return;
    }
    final client = Talaria.getClient();
    if (client == null) {
      return;
    }
    // ignore: discarded_futures
    client.captureException(
      event.exception,
      stackTrace: event.stackTrace,
      context: CaptureContext(
        mechanism: const ExceptionMechanism(
          type: 'serverpod_diagnostic',
          handled: false,
        ),
        title: event.message,
      ),
    );
  }

  /// Reset attach flag between tests.
  static void resetAttachForTest() {
    _attached = false;
  }

  static void _ensureSessionTransaction(
    TalariaClient client,
    Session session,
  ) {
    final sessionId = SessionSpans.sessionIdOf(session);
    final result = SessionTransaction.bindOrStart(
      client: client,
      sessionId: sessionId,
      name: SessionSpans.name(session),
      kind: SessionSpans.kind(session),
      attributes: SessionSpans.attributes(session),
      isFutureCall: session is FutureCallSession,
      userId: _sessionUserId(session),
    );
    if (!result.created) {
      return;
    }
    session.addWillCloseListener((_) {
      final bound = SpanScope.forSession(sessionId);
      bound?.finish();
      SpanScope.unbindSession(sessionId);
    });
  }

  static String? _sessionUserId(Session session) {
    try {
      final id = session.authenticated?.userIdentifier.trim();
      if (id == null || id.isEmpty) {
        return null;
      }
      return id;
    } catch (_) {
      return null;
    }
  }
}
