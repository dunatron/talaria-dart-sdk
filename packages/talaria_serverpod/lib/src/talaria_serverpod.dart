import 'package:serverpod/serverpod.dart';
import 'package:talaria/talaria.dart';

import 'diagnostic_filter.dart';
import 'io_http.dart';
import 'relic_middleware.dart';
import 'session_spans.dart';
import 'session_transaction.dart';
import 'tracing_database.dart';

/// Serverpod adapter: Relic SERVER spans, Postgres CLIENT spans, FutureCalls.
class TalariaServerpod {
  TalariaServerpod._();

  static bool _attached = false;

  /// Record rejected API calls (bad key, expired key, quota, rate limit,
  /// missing project access) instead of treating them as expected noise.
  ///
  /// The Talaria server turns this on for its own dogfood project. Other
  /// Serverpod apps keep the quieter default. Socket disconnects and the
  /// generic handler wrapper stay dropped either way.
  static bool get captureRejectedRequests =>
      DiagnosticFilter.captureRejectedRequests;

  static set captureRejectedRequests(bool value) {
    DiagnosticFilter.captureRejectedRequests = value;
  }
  static final Map<String, String> _sessionUsers = {};
  static final Set<String> _userCloseHook = {};
  static final Map<String, Map<String, String>> _sessionTags = {};
  static final Set<String> _tagCloseHook = {};

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
    ).whenComplete(installServerpodOutboundHttp);
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

    final sessionId = context is OperationEventContext
        ? context.sessionId?.toString()
        : null;
    final resolvedSessionId =
        (sessionId != null && sessionId.isNotEmpty) ? sessionId : null;
    final uri = context is ClientCallOpContext ? context.uri.toString() : null;
    final userId = context is OperationEventContext
        ? context.userAuthInfo?.userIdentifier.trim()
        : null;
    final fromSession = resolvedSessionId == null
        ? null
        : _sessionUsers[resolvedSessionId];
    final resolvedUserId = _firstUser(userId, fromSession);

    final sameRequest = uri != null &&
        uri.isNotEmpty &&
        RuntimeContext.zoneUrl == uri;

    if (resolvedSessionId != null &&
        SpanScope.forSession(resolvedSessionId) == null &&
        sameRequest) {
      final current = client.tracer.currentSpan;
      if (current != null && current.isRecording) {
        SpanScope.bindSession(resolvedSessionId, current);
      }
    }

    final callerTags = resolvedSessionId == null
        ? null
        : _sessionTags[resolvedSessionId];
    final tags = callerTags == null || callerTags.isEmpty
        ? null
        : Map<String, String>.from(callerTags);

    final attached = resolvedSessionId == null
        ? null
        : SpanScope.forSession(resolvedSessionId);
    if (attached != null && attached.isRecording) {
      SessionTransaction.applyUser(attached, resolvedUserId);
      if (tags != null) {
        for (final entry in tags.entries) {
          attached.setAttribute(entry.key, entry.value);
        }
      }
      attached.markError(message: event.exception.toString());
    }

    final crumbs = _crumbsForDiagnostic(
      sessionId: resolvedSessionId,
      sameRequest: sameRequest,
    );

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
          tags: tags,
        ),
      );
    }

    Future<void> scopedCapture() {
      return BreadcrumbScope.runWithAsync(capture, buffer: crumbs);
    }

    // ignore: discarded_futures
    RuntimeContext.runWithAsync(
      () async {
        if (resolvedSessionId != null) {
          await SpanScope.runAsync(
            scopedCapture,
            sessionId: resolvedSessionId,
          );
          return;
        }
        if (sameRequest) {
          await scopedCapture();
          return;
        }
        await SpanScope.runAsync(scopedCapture);
      },
      url: uri,
      requestId: resolvedSessionId,
      userId: resolvedUserId,
      blankUnset: true,
    );
  }

  /// Crumbs from the throwing session. A foreign Zone's buffer is ignored.
  static BreadcrumbBuffer _crumbsForDiagnostic({
    required String? sessionId,
    required bool sameRequest,
  }) {
    if (sessionId != null) {
      final bound = BreadcrumbScope.forSession(sessionId);
      if (bound != null) {
        return bound;
      }
    }
    if (sameRequest) {
      final zoneCrumbs = BreadcrumbScope.zoneBuffer();
      if (zoneCrumbs != null) {
        if (sessionId != null) {
          BreadcrumbScope.bindSession(sessionId, zoneCrumbs);
        }
        return zoneCrumbs;
      }
    }
    return BreadcrumbBuffer();
  }

  /// Remember caller identity for this Serverpod session only.
  ///
  /// Diagnostic capture copies these tags onto the event. They do not go
  /// through [TalariaClient.setUser], which is process-wide.
  static void bindRequestTags(Session session, Map<String, String> tags) {
    final sessionId = SessionSpans.sessionIdOf(session);
    bindSessionTags(sessionId, tags);
    if (sessionId.isEmpty || !_tagCloseHook.add(sessionId)) {
      return;
    }
    session.addWillCloseListener((_) {
      _tagCloseHook.remove(sessionId);
      _sessionTags.remove(sessionId);
    });
  }

  /// Test and internal entry. Empty keys and values are ignored. Later calls
  /// merge into tags already stored for the session.
  static void bindSessionTags(String sessionId, Map<String, String> tags) {
    final id = sessionId.trim();
    if (id.isEmpty || tags.isEmpty) {
      return;
    }
    final current = _sessionTags.putIfAbsent(id, () => {});
    for (final entry in tags.entries) {
      final key = entry.key.trim();
      final value = entry.value.trim();
      if (key.isEmpty || value.isEmpty) continue;
      current[key] = value;
    }
    if (current.isEmpty) {
      _sessionTags.remove(id);
    }
  }

  /// Remember the dashboard user for this Serverpod session only.
  ///
  /// Diagnostic capture reads this map. It does not call [TalariaClient.setUser],
  /// which is process-wide and would leak across concurrent requests.
  static void bindRequestUser(Session session, String userId) {
    final sessionId = SessionSpans.sessionIdOf(session);
    bindSessionUser(sessionId, userId);
    if (sessionId.isEmpty || !_userCloseHook.add(sessionId)) {
      return;
    }
    session.addWillCloseListener((_) {
      _userCloseHook.remove(sessionId);
      unbindSessionUser(sessionId);
    });
  }

  /// Test and internal entry. [userId] is trimmed; empty values are ignored.
  static void bindSessionUser(String sessionId, String userId) {
    final id = sessionId.trim();
    final user = userId.trim();
    if (id.isEmpty || user.isEmpty) {
      return;
    }
    _sessionUsers[id] = user;
    final span = SpanScope.forSession(id);
    if (span != null && span.isRecording) {
      SessionTransaction.applyUser(span, user);
    }
  }

  static void unbindSessionUser(String sessionId) {
    _sessionUsers.remove(sessionId.trim());
  }

  static void clearSessionUsersForTest() {
    _sessionUsers.clear();
    _userCloseHook.clear();
    _sessionTags.clear();
    _tagCloseHook.clear();
    captureRejectedRequests = false;
  }

  static String? _firstUser(String? primary, String? fallback) {
    final first = primary?.trim();
    if (first != null && first.isNotEmpty) {
      return first;
    }
    final second = fallback?.trim();
    if (second != null && second.isNotEmpty) {
      return second;
    }
    return null;
  }

  /// Reset attach flag between tests.
  static void resetAttachForTest() {
    _attached = false;
    clearSessionUsersForTest();
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
      SessionTransaction.finish(SpanScope.forSession(sessionId));
      SpanScope.unbindSession(sessionId);
      BreadcrumbScope.unbindSession(sessionId);
      unbindSessionUser(sessionId);
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
