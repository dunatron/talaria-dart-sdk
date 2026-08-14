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

  static String? _url;
  static String? _requestId;

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

  static void setCurrent({String? url, String? requestId}) {
    if (url != null) {
      setUrl(url);
    }
    if (requestId != null) {
      setRequestId(requestId);
    }
  }

  static void clearCurrent() {
    _url = null;
    _requestId = null;
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
