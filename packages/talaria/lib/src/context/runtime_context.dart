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

  /// Zone value meaning "this field is intentionally unset".
  ///
  /// Getters then return null instead of a parent Zone value or the isolate
  /// fallback. Diagnostic capture uses this so one request cannot inherit
  /// another's URL or user id.
  static const Object unset = #talariaRuntimeUnset;

  static String? _url;
  static String? _requestId;
  static String? _userAgent;
  static String? _locale;
  static String? _timezone;
  static String? _osName;
  static String? _osVersion;
  static String? _device;
  static String? _browserName;
  static String? _browserVersion;
  static String? _browserEngine;
  static String? _userId;
  static String? _anonymousId;
  static String? _sessionId;
  static String? _replayId;

  /// Isolate-wide current URL (Flutter route, Dart request URL, …).
  static String? get url => _zoneOrIsolate(urlZoneKey, _url);

  /// URL bound on this Zone only. Ignores the isolate fallback.
  static String? get zoneUrl => _zoneOnly(urlZoneKey);

  /// Isolate-wide current request id (inbound `X-Request-Id`, span id, …).
  static String? get requestId => _zoneOrIsolate(requestIdZoneKey, _requestId);

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

  static String? get locale => _locale;

  static String? get timezone => _timezone;

  static String? get osName => _osName;

  static String? get osVersion => _osVersion;

  static String? get device => _device;

  static String? get browserName => _browserName;

  static String? get browserVersion => _browserVersion;

  static String? get browserEngine => _browserEngine;

  /// Zone-local user id (JWT / session), then isolate fallback.
  static String? get userId => _zoneOrIsolate(userIdZoneKey, _userId);

  static void setUserAgent(String? userAgent) {
    final trimmed = userAgent?.trim();
    _userAgent = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static void setLocale(String? locale) {
    final trimmed = locale?.trim();
    _locale = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static void setTimezone(String? timezone) {
    final trimmed = timezone?.trim();
    _timezone = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static void setOsName(String? osName) {
    _osName = _trimOrNull(osName);
  }

  static void setOsVersion(String? osVersion) {
    _osVersion = _trimOrNull(osVersion);
  }

  static void setDevice(String? device) {
    _device = _trimOrNull(device);
  }

  static void setBrowserName(String? browserName) {
    _browserName = _trimOrNull(browserName);
  }

  static void setBrowserVersion(String? browserVersion) {
    _browserVersion = _trimOrNull(browserVersion);
  }

  static void setBrowserEngine(String? browserEngine) {
    _browserEngine = _trimOrNull(browserEngine);
  }

  static String? _trimOrNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static void setUserId(String? userId) {
    final trimmed = userId?.trim();
    _userId = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Zone-local then isolate fallback. Used by server Dart per request.
  static String? get anonymousId =>
      _zoneOrIsolate(anonymousIdZoneKey, _anonymousId);

  static void setAnonymousId(String? anonymousId) {
    final trimmed = anonymousId?.trim();
    _anonymousId = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static String? get sessionId => _zoneOrIsolate(sessionIdZoneKey, _sessionId);

  static void setSessionId(String? sessionId) {
    final trimmed = sessionId?.trim();
    _sessionId = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static String? get replayId => _zoneOrIsolate(replayIdZoneKey, _replayId);

  static String? _zoneOnly(Object key) {
    final fromZone = Zone.current[key];
    if (identical(fromZone, unset)) {
      return null;
    }
    if (fromZone is String && fromZone.isNotEmpty) {
      return fromZone;
    }
    return null;
  }

  static String? _zoneOrIsolate(Object key, String? isolate) {
    final fromZone = Zone.current[key];
    if (identical(fromZone, unset)) {
      return null;
    }
    if (fromZone is String && fromZone.isNotEmpty) {
      return fromZone;
    }
    return isolate;
  }

  static Map<Object?, Object?> _zoneValues({
    String? url,
    String? requestId,
    String? userId,
    String? anonymousId,
    String? sessionId,
    String? replayId,
    bool blankUnset = false,
  }) {
    final values = <Object?, Object?>{};
    void put(Object key, String? value) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        values[key] = trimmed;
        return;
      }
      if (blankUnset) {
        values[key] = unset;
      }
    }

    put(urlZoneKey, url);
    put(requestIdZoneKey, requestId);
    put(userIdZoneKey, userId);
    put(anonymousIdZoneKey, anonymousId);
    put(sessionIdZoneKey, sessionId);
    put(replayIdZoneKey, replayId);
    return values;
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
    _userAgent = null;
    _locale = null;
    _timezone = null;
    _osName = null;
    _osVersion = null;
    _device = null;
    _browserName = null;
    _browserVersion = null;
    _browserEngine = null;
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
    bool blankUnset = false,
  }) {
    return Zone.current.fork(
      zoneValues: _zoneValues(
        url: url,
        requestId: requestId,
        userId: userId,
        anonymousId: anonymousId,
        sessionId: sessionId,
        replayId: replayId,
        blankUnset: blankUnset,
      ),
    ).run(body);
  }

  /// Async variant of [runWith].
  ///
  /// When [blankUnset] is true, omitted request fields are explicitly empty
  /// and do not inherit a parent Zone or the isolate fallback.
  static Future<T> runWithAsync<T>(
    Future<T> Function() body, {
    String? url,
    String? requestId,
    String? userId,
    String? anonymousId,
    String? sessionId,
    String? replayId,
    bool blankUnset = false,
  }) {
    return Zone.current.fork(
      zoneValues: _zoneValues(
        url: url,
        requestId: requestId,
        userId: userId,
        anonymousId: anonymousId,
        sessionId: sessionId,
        replayId: replayId,
        blankUnset: blankUnset,
      ),
    ).run(body);
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
    final fraction = (t.millisecond * 1000 + t.microsecond)
        .toString()
        .padLeft(6, '0');
    var trimmed = fraction;
    while (trimmed.length > 3 && trimmed.endsWith('0')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return '$y-$mo-$d'
        'T'
        '$h:$mi:$s.$trimmed'
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
