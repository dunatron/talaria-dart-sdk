import 'dart:convert';

import '../context/runtime_context.dart';
import 'storage.dart';
import 'utm.dart';

/// Durable visitor + session ids shared by events, spans, and analytics.
class Identity {
  Identity({
    TalariaStorage? storage,
    DateTime Function()? clock,
    String? seedAnonymousId,
  })  : _storage = storage ?? MemoryTalariaStorage(),
        _clock = clock ?? DateTime.now {
    final existing = _storage.read(anonymousIdKey);
    if (existing != null && existing.isNotEmpty) {
      _anonymousId = existing;
    } else if (seedAnonymousId != null && seedAnonymousId.isNotEmpty) {
      _anonymousId = seedAnonymousId;
      _persist(anonymousIdKey, _anonymousId);
    } else {
      _anonymousId = RuntimeContext.newSessionId();
      _persist(anonymousIdKey, _anonymousId);
    }

    final storedSession = _storage.read(sessionIdKey);
    final storedTouched = _parseTime(_storage.read(sessionTouchedAtKey));
    final now = _now();
    if (storedSession != null &&
        storedSession.isNotEmpty &&
        storedTouched != null &&
        !_shouldRotate(storedTouched, now)) {
      _sessionId = storedSession;
      _touchedAt = storedTouched;
    } else {
      _rotateSession(now);
    }

    _utm = Utm.fromMap(_decodeMap(_storage.read(utmKey)));
  }

  static const anonymousIdKey = 'talaria.anonymousId';
  static const sessionIdKey = 'talaria.sessionId';
  static const sessionTouchedAtKey = 'talaria.sessionTouchedAt';
  static const utmKey = 'talaria.utm';
  static const sessionTimeout = Duration(minutes: 30);

  final TalariaStorage _storage;
  final DateTime Function() _clock;

  late String _anonymousId;
  late String _sessionId;
  late DateTime _touchedAt;
  Utm? _utm;

  String get anonymousId => _anonymousId;

  String get sessionId => _sessionId;

  Utm? get firstTouchUtm => _utm;

  DateTime get lastTouchedAt => _touchedAt;

  /// Refresh session activity; rotate after 30 minutes idle or midnight UTC.
  String touch() {
    final now = _now();
    if (_shouldRotate(_touchedAt, now)) {
      _rotateSession(now);
    } else {
      _touchedAt = now;
      _persist(sessionTouchedAtKey, RuntimeContext.isoTimestamp(now));
    }
    return _sessionId;
  }

  /// New visitor: new anonymousId + session, drop first-touch UTM.
  Future<void> reset() async {
    _anonymousId = RuntimeContext.newSessionId();
    await _storage.write(anonymousIdKey, _anonymousId);
    await _storage.delete(utmKey);
    _utm = null;
    _rotateSession(_now());
  }

  /// Capture first-touch UTM from [url] when none is stored yet.
  void captureUtmFromUrl(String? url) {
    if (_utm != null) {
      return;
    }
    final found = Utm.fromUrl(url);
    if (found == null) {
      return;
    }
    _utm = found;
    _persist(utmKey, jsonEncode(found.toMap()));
  }

  DateTime _now() => _clock().toUtc();

  void _rotateSession(DateTime now) {
    _sessionId = RuntimeContext.newSessionId();
    _touchedAt = now;
    _persist(sessionIdKey, _sessionId);
    _persist(sessionTouchedAtKey, RuntimeContext.isoTimestamp(now));
  }

  bool _shouldRotate(DateTime lastTouch, DateTime now) {
    if (now.difference(lastTouch) >= sessionTimeout) {
      return true;
    }
    final last = lastTouch.toUtc();
    final current = now.toUtc();
    return last.year != current.year ||
        last.month != current.month ||
        last.day != current.day;
  }

  void _persist(String key, String value) {
    // ignore: discarded_futures
    _storage.write(key, value);
  }

  static DateTime? _parseTime(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }

  static Map<String, Object?>? _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, Object?>.from(decoded);
      }
    } catch (_) {}
    return null;
  }
}
