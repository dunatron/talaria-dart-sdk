import 'dart:convert';

/// Classification of an ingest HTTP error body.
class IngestError {
  const IngestError({
    this.className,
    this.message,
    this.retry,
  });

  final String? className;
  final String? message;
  final bool? retry;

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
