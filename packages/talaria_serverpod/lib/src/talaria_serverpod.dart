import 'package:serverpod/serverpod.dart';
import 'package:talaria/talaria.dart';

import 'diagnostic_filter.dart';
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
  static void handleExceptionEvent(
    ExceptionEvent event, {
    DiagnosticEventContext? context,
  }) {
    if (DiagnosticFilter.shouldDrop(event)) {
      return;
    }
    final client = Talaria.getClient();
    if (client == null) {
      return;
    }

    final sessionId =
        context is OperationEventContext ? context.sessionId?.toString() : null;
    final uri = context is ClientCallOpContext ? context.uri.toString() : null;
    final userId = context is OperationEventContext
        ? context.userAuthInfo?.userIdentifier.trim()
        : null;
    final resolvedUserId =
        (userId != null && userId.isNotEmpty) ? userId : null;

    if (sessionId != null && sessionId.isNotEmpty) {
      final zoneCrumbs = BreadcrumbScope.zoneBuffer();
      if (zoneCrumbs != null) {
        BreadcrumbScope.bindSession(sessionId, zoneCrumbs);
      }
    }

    Future<void> capture() {
      return client.captureException(
        event.exception,
        stackTrace: event.stackTrace,
        context: CaptureContext(
          mechanism: const ExceptionMechanism(
            type: 'serverpod_diagnostic',
            handled: false,
          ),
          title: DiagnosticFilter.titleOf(event),
          userId: resolvedUserId,
        ),
      );
    }

    // ignore: discarded_futures
    RuntimeContext.runWithAsync(
      () async {
        if (sessionId != null && sessionId.isNotEmpty) {
          await SpanScope.runAsync(
            capture,
            sessionId: sessionId,
          );
        } else {
          await capture();
        }
      },
      url: uri,
      requestId: sessionId,
      userId: resolvedUserId,
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
    final zoneCrumbs = BreadcrumbScope.zoneBuffer();
    if (zoneCrumbs != null) {
      BreadcrumbScope.bindSession(sessionId, zoneCrumbs);
    }
    if (!result.created) {
      return;
    }
    session.addWillCloseListener((_) {
      final bound = SpanScope.forSession(sessionId);
      bound?.finish();
      SpanScope.unbindSession(sessionId);
      BreadcrumbScope.unbindSession(sessionId);
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
