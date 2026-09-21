import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'platform_info_stub.dart' if (dart.library.io) 'platform_info_io.dart'
    as platform_info;

/// Best-effort runtime context for auto-enrichment.
class RuntimeContext {
  RuntimeContext._();

  static const Object urlZoneKey = #talariaRuntimeUrl;
  static const Object requestIdZoneKey = #talariaRuntimeRequestId;
  static const Object userIdZoneKey = #talariaRuntimeUserId;
  static const Object anonymousIdZoneKey = #talariaRuntimeAnonymousId;
  static const Object sessionIdZoneKey = #talariaRuntimeSessionId;
  static const Object replayIdZoneKey = #talariaRuntimeReplayId;

  static String? _url;
  static String? _requestId;
  static String? _userAgent;
  static String? _userId;
  static String? _anonymousId;
  static String? _sessionId;
  static String? _replayId;

  /// Isolate-wide current URL (Flutter route, Dart request URL, …).
  static String? get url {
    final fromZone = Zone.current[urlZoneKey];
    if (fromZone is String && fromZone.isNotEmpty) {
      return fromZone;
    }
    return _url;
  }

  /// Isolate-wide current request id (inbound `X-Request-Id`, span id, …).
  static String? get requestId {
    final fromZone = Zone.current[requestIdZoneKey];
    if (fromZone is String && fromZone.isNotEmpty) {
      return fromZone;
    }
    return _requestId;
  }

  static void setUrl(String? url) {
    final trimmed = url?.trim();
    _url = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static void setRequestId(String? requestId) {
    final trimmed = requestId?.trim();
    _requestId = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Process-wide browser / device user agent when the host collected one.
  static String? get userAgent => _userAgent;

  /// Zone-local user id (JWT / session), then isolate fallback.
  static String? get userId {
    final fromZone = Zone.current[userIdZoneKey];
    if (fromZone is String && fromZone.isNotEmpty) {
      return fromZone;
    }
    return _userId;
  }

  static void setUserAgent(String? userAgent) {
    final trimmed = userAgent?.trim();
    _userAgent = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static void setUserId(String? userId) {
    final trimmed = userId?.trim();
    _userId = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Zone-local then isolate fallback. Used by server Dart per request.
  static String? get anonymousId {
    final fromZone = Zone.current[anonymousIdZoneKey];
    if (fromZone is String && fromZone.isNotEmpty) {
      return fromZone;
    }
    return _anonymousId;
  }

  static void setAnonymousId(String? anonymousId) {
    final trimmed = anonymousId?.trim();
    _anonymousId = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static String? get sessionId {
    final fromZone = Zone.current[sessionIdZoneKey];
    if (fromZone is String && fromZone.isNotEmpty) {
      return fromZone;
    }
    return _sessionId;
  }

  static void setSessionId(String? sessionId) {
    final trimmed = sessionId?.trim();
    _sessionId = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static String? get replayId {
    final fromZone = Zone.current[replayIdZoneKey];
    if (fromZone is String && fromZone.isNotEmpty) {
      return fromZone;
    }
    return _replayId;
  }

  static void setReplayId(String? replayId) {
    final trimmed = replayId?.trim();
    _replayId = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static void setCurrent({
    String? url,
    String? requestId,
    String? userId,
    String? anonymousId,
    String? sessionId,
    String? replayId,
  }) {
    if (url != null) {
      setUrl(url);
    }
    if (requestId != null) {
      setRequestId(requestId);
    }
    if (userId != null) {
      setUserId(userId);
    }
    if (anonymousId != null) {
      setAnonymousId(anonymousId);
    }
    if (sessionId != null) {
      setSessionId(sessionId);
    }
    if (replayId != null) {
      setReplayId(replayId);
    }
  }

  static void clearCurrent() {
    _url = null;
    _requestId = null;
    _userId = null;
    _anonymousId = null;
    _sessionId = null;
    _replayId = null;
  }

  /// Bind request URL / ids on this Zone only (no isolate-wide leak).
  static T runWith<T>(
    T Function() body, {
    String? url,
    String? requestId,
    String? userId,
    String? anonymousId,
    String? sessionId,
    String? replayId,
  }) {
    return Zone.current.fork(zoneValues: {
      if (url != null && url.isNotEmpty) urlZoneKey: url,
      if (requestId != null && requestId.isNotEmpty)
        requestIdZoneKey: requestId,
      if (userId != null && userId.isNotEmpty) userIdZoneKey: userId,
      if (anonymousId != null && anonymousId.isNotEmpty)
        anonymousIdZoneKey: anonymousId,
      if (sessionId != null && sessionId.isNotEmpty)
        sessionIdZoneKey: sessionId,
      if (replayId != null && replayId.isNotEmpty) replayIdZoneKey: replayId,
    }).run(body);
  }

  /// Async variant of [runWith].
  static Future<T> runWithAsync<T>(
    Future<T> Function() body, {
    String? url,
    String? requestId,
    String? userId,
    String? anonymousId,
    String? sessionId,
    String? replayId,
  }) {
    return Zone.current.fork(zoneValues: {
      if (url != null && url.isNotEmpty) urlZoneKey: url,
      if (requestId != null && requestId.isNotEmpty)
        requestIdZoneKey: requestId,
      if (userId != null && userId.isNotEmpty) userIdZoneKey: userId,
      if (anonymousId != null && anonymousId.isNotEmpty)
        anonymousIdZoneKey: anonymousId,
      if (sessionId != null && sessionId.isNotEmpty)
        sessionIdZoneKey: sessionId,
      if (replayId != null && replayId.isNotEmpty) replayIdZoneKey: replayId,
    }).run(body);
  }

  static Map<String, Object?> collect({String runtime = 'dart'}) {
    final tags = <String, String>{
      'runtime': runtime,
      ...platform_info.platformTags(),
    };
    final version = platform_info.dartVersion();
    if (version != null && !tags.containsKey('dart.version')) {
      tags['dart.version'] = version;
    }

    final extra = <String, Object?>{
      ...platform_info.platformExtra(),
    };

    return {
      'url': url,
      'requestId': requestId,
      'tags': tags,
      'extra': extra,
    };
  }

  static String newSessionId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// UUID v4 for analytics `eventId`.
  static String newUuid() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  static String isoTimestamp([DateTime? now]) {
    final t = (now ?? DateTime.now()).toUtc();
    final y = t.year.toString().padLeft(4, '0');
    final mo = t.month.toString().padLeft(2, '0');
    final d = t.day.toString().padLeft(2, '0');
    final h = t.hour.toString().padLeft(2, '0');
    final mi = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    final ms = t.millisecond.toString().padLeft(3, '0');
    return '$y-$mo-$d'
        'T'
        '$h:$mi:$s.$ms'
        'Z';
  }

  /// Encode extra map as a JSON object string for `extraJson`.
  static String? encodeExtraJson(Map<String, Object?> extra) {
    if (extra.isEmpty) {
      return null;
    }
    try {
      return jsonEncode(extra);
    } catch (_) {
      return null;
    }
  }
}
