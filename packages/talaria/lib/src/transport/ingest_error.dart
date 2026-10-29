import 'dart:convert';

/// Classification of an ingest HTTP error body.
class IngestError {
  const IngestError({
    this.className,
    this.message,
    this.retry,
    this.retryAfterSeconds,
    this.meter,
    this.resetAt,
  });

  final String? className;
  final String? message;
  final bool? retry;

  /// `retryAfterSeconds` on `ApiRateLimitedException`.
  final int? retryAfterSeconds;

  /// `meter` on `ApiQuotaExceededException`.
  final String? meter;

  /// Quota period reset on `ApiQuotaExceededException`: `resetAt` (also
  /// `resetsAt`, `periodResetAt`, `periodEnd`), as ISO 8601 or epoch seconds
  /// or milliseconds.
  final DateTime? resetAt;

  /// Parse a Serverpod exception JSON body (`className` or `__className__`).
  static IngestError parse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        return const IngestError();
      }
      final nested = decoded['data'];
      final nestedMap = nested is Map ? nested : const <Object?, Object?>{};
      return IngestError(
        className: _stringOf(
          decoded['__className__'] ??
              decoded['className'] ??
              decoded['exception'] ??
              nestedMap['__className__'],
        ),
        message: _stringOf(decoded['message'] ?? nestedMap['message']),
        retry: _boolOf(decoded['retry'] ?? nestedMap['retry']),
        retryAfterSeconds: _intOf(
          decoded['retryAfterSeconds'] ?? nestedMap['retryAfterSeconds'],
        ),
        meter: _stringOf(decoded['meter'] ?? nestedMap['meter']),
        resetAt: _firstDate(decoded, nestedMap),
      );
    } catch (_) {
      return const IngestError();
    }
  }

  /// Permanent failures: dead API key, missing project, disallowed origin.
  /// Quota / rate-limit / 5xx are never permanent.
  bool get isPermanent {
    if (retry == true) {
      return false;
    }
    if (retry == false) {
      return true;
    }
    final name = className ?? '';
    if (name.contains('ApiUnauthorizedException')) {
      return true;
    }
    if (name.contains('ApiDisallowedDomainException')) {
      return true;
    }
    if (name.contains('ApiNotFoundException')) {
      return true;
    }
    if (name.contains('ApiConflictException') &&
        (message ?? '').toLowerCase().contains('not active')) {
      return true;
    }
    return false;
  }

  bool get isGlobalCredentialFailure {
    final name = className ?? '';
    return name.contains('ApiUnauthorizedException') ||
        name.contains('ApiDisallowedDomainException') ||
        name.contains('ApiNotFoundException');
  }

  /// Tracing, analytics, or replay disabled on the project. Not a dead key.
  String? get disabledSignal {
    if (!isPermanent || isGlobalCredentialFailure || isScopeOnly) return null;
    final text = (message ?? '').toLowerCase();
    if (text.contains('tracing is disabled') ||
        text.contains('performance is disabled')) {
      return 'spans';
    }
    if (text.contains('analytics is disabled')) return 'analytics';
    if (text.contains('session replay is disabled')) return 'replay';
    return null;
  }

  /// Missing a single scope — disable that signal only, not the whole client.
  bool get isScopeOnly {
    final msg = (message ?? '').toLowerCase();
    return msg.contains('lacks required scope');
  }

  static String? _stringOf(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  static const _resetKeys = [
    'resetAt',
    'resetsAt',
    'periodResetAt',
    'periodEnd',
  ];

  static DateTime? _firstDate(
    Map<Object?, Object?> a,
    Map<Object?, Object?> b,
  ) {
    for (final key in _resetKeys) {
      final value = dateOf(a[key] ?? b[key]);
      if (value != null) return value;
    }
    return null;
  }

  /// ISO 8601 string, or epoch seconds or milliseconds. UTC.
  static DateTime? dateOf(Object? value) {
    if (value is String) {
      return DateTime.tryParse(value.trim())?.toUtc();
    }
    if (value is num && value > 0) {
      final ms = value < 1e12 ? value * 1000 : value;
      return DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true);
    }
    return null;
  }

  static int? _intOf(Object? value) {
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static bool? _boolOf(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is String) {
      switch (value.toLowerCase().trim()) {
        case 'true':
        case '1':
          return true;
        case 'false':
        case '0':
          return false;
      }
    }
    return null;
  }
}

/// Which ingest path a permanent error applies to.
enum IngestSignal { events, spans, replay, analytics }
