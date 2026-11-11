import 'dart:convert';

/// Closed set of problem+json `code` values the SDK classifies (TR-6, IB3).
/// Unknown codes parse as null and are not permanent.
enum IngestProblemCode {
  invalidKey,
  insufficientScope,
  forbiddenOrigin,
  wrongCell,
  invalidBody,
  invalidRelease,
  quotaExceeded,
  ingestBlocked,
  rateLimited,
  notFound,
  invalidScope;

  String get wire => switch (this) {
        IngestProblemCode.invalidKey => 'invalid_key',
        IngestProblemCode.insufficientScope => 'insufficient_scope',
        IngestProblemCode.forbiddenOrigin => 'forbidden_origin',
        IngestProblemCode.wrongCell => 'wrong_cell',
        IngestProblemCode.invalidBody => 'invalid_body',
        IngestProblemCode.invalidRelease => 'invalid_release',
        IngestProblemCode.quotaExceeded => 'quota_exceeded',
        IngestProblemCode.ingestBlocked => 'ingest_blocked',
        IngestProblemCode.rateLimited => 'rate_limited',
        IngestProblemCode.notFound => 'not_found',
        IngestProblemCode.invalidScope => 'invalid_scope',
      };

  static IngestProblemCode? tryParse(String? code) {
    if (code == null || code.isEmpty) return null;
    for (final value in IngestProblemCode.values) {
      if (value.wire == code) return value;
    }
    return null;
  }

  /// Seconds an SDK waits after `ingest_blocked`, clamped 15 minutes to 24 hours.
  static const minRetryAfterSeconds = 15 * 60;
  static const maxRetryAfterSeconds = 24 * 60 * 60;

  static int clampRetryAfter(int? seconds) {
    final value = seconds ?? minRetryAfterSeconds;
    if (value < minRetryAfterSeconds) return minRetryAfterSeconds;
    if (value > maxRetryAfterSeconds) return maxRetryAfterSeconds;
    return value;
  }
}

/// Classification of an ingest HTTP error body.
class IngestError {
  const IngestError({
    this.code,
    this.className,
    this.message,
    this.retry,
    this.retryAfterSeconds,
    this.reason,
    this.meter,
    this.resetAt,
    this.status,
    this.type,
    this.title,
    this.requestId,
    this.cell,
    this.cellUrl,
  });

  /// Problem+json `code` (`invalid_key`, `rate_limited`, …).
  final String? code;
  final String? className;
  final String? message;
  final bool? retry;

  /// `retryAfterSeconds` when a problem body includes it.
  final int? retryAfterSeconds;

  /// Block reason (`org_unpaid`, `trial_expired`, …) on `ingest_blocked`.
  final String? reason;

  /// Quota meter, when the problem body includes it.
  final String? meter;

  /// Quota period reset: `resetAt` (also `resetsAt`, `periodResetAt`,
  /// `periodEnd`), as ISO 8601 or epoch seconds or milliseconds.
  final DateTime? resetAt;

  final int? status;
  final String? type;
  final String? title;
  final String? requestId;
  final String? cell;

  /// `url` extension on `wrong_cell`.
  final String? cellUrl;

  static const permanentCodes = {
    'invalid_key',
    'not_found',
    'insufficient_scope',
    'invalid_scope',
    'wrong_cell',
    'invalid_body',
    'invalid_release',
    'forbidden_origin',
  };

  /// Parse an RFC 9457 `application/problem+json` body.
  static IngestError parse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        return const IngestError();
      }
      final code = _stringOf(decoded['code']);
      final parsed = IngestProblemCode.tryParse(code);
      return IngestError(
        code: code,
        message: _stringOf(decoded['detail'] ?? decoded['title']),
        retry: switch (parsed) {
          IngestProblemCode.rateLimited ||
          IngestProblemCode.quotaExceeded ||
          IngestProblemCode.ingestBlocked =>
            true,
          IngestProblemCode.invalidKey ||
          IngestProblemCode.insufficientScope ||
          IngestProblemCode.forbiddenOrigin ||
          IngestProblemCode.wrongCell ||
          IngestProblemCode.invalidBody ||
          IngestProblemCode.invalidRelease ||
          IngestProblemCode.notFound ||
          IngestProblemCode.invalidScope =>
            false,
          null => null,
        },
        retryAfterSeconds: _intOf(decoded['retryAfterSeconds']),
        reason: _stringOf(decoded['reason']),
        meter: _stringOf(decoded['meter']),
        resetAt: _firstDate(decoded, const {}),
        status: _intOf(decoded['status']),
        type: _stringOf(decoded['type']),
        title: _stringOf(decoded['title']),
        requestId: _stringOf(decoded['requestId']),
        cell: _stringOf(decoded['cell']),
        cellUrl: _stringOf(decoded['url']),
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
    final parsed = IngestProblemCode.tryParse(code);
    if (parsed != null) {
      return switch (parsed) {
        IngestProblemCode.invalidKey ||
        IngestProblemCode.insufficientScope ||
        IngestProblemCode.forbiddenOrigin ||
        IngestProblemCode.wrongCell ||
        IngestProblemCode.invalidBody ||
        IngestProblemCode.invalidRelease ||
        IngestProblemCode.notFound ||
        IngestProblemCode.invalidScope =>
          true,
        IngestProblemCode.rateLimited ||
        IngestProblemCode.quotaExceeded ||
        IngestProblemCode.ingestBlocked =>
          false,
      };
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

  bool get isIngestBlocked =>
      IngestProblemCode.tryParse(code) == IngestProblemCode.ingestBlocked;

  bool get isForbiddenOrigin =>
      IngestProblemCode.tryParse(code) == IngestProblemCode.forbiddenOrigin;

  bool get isGlobalCredentialFailure {
    switch (IngestProblemCode.tryParse(code)) {
      case IngestProblemCode.invalidKey ||
            IngestProblemCode.notFound ||
            IngestProblemCode.wrongCell:
        return true;
      case IngestProblemCode.insufficientScope ||
            IngestProblemCode.forbiddenOrigin ||
            IngestProblemCode.invalidBody ||
            IngestProblemCode.invalidRelease ||
            IngestProblemCode.quotaExceeded ||
            IngestProblemCode.ingestBlocked ||
            IngestProblemCode.rateLimited ||
            IngestProblemCode.invalidScope:
        return false;
      case null:
        break;
    }
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
    if (code == 'insufficient_scope') return true;
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
}

/// Which ingest path a permanent error applies to.
enum IngestSignal { events, spans, replay, analytics }
