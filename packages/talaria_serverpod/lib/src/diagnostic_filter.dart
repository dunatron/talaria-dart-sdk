import 'package:serverpod/serverpod.dart';
import 'package:talaria/src/protocol/exception_payload_builder.dart';

import 'session_transaction.dart';

/// Expected Serverpod diagnostics that must not become Talaria Issues.
class DiagnosticFilter {
  DiagnosticFilter._();

  static final _uuidInTitle = RegExp(
    r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
    caseSensitive: false,
  );

  static bool shouldDrop(ExceptionEvent event) {
    if (SessionTransaction.isGenericDiagnosticMessage(event.message)) {
      return true;
    }
    return isExpectedException(event.exception, message: event.message);
  }

  static bool isExpectedException(Object error, {String? message}) {
    if (error is NotAuthorizedException) {
      return true;
    }
    final type = error.runtimeType.toString();
    if (type.contains('ApiUnauthorizedException')) {
      return true;
    }
    if (type.contains('QuotaExceeded')) {
      return true;
    }
    if (type.contains('WebSocketConnectionClosed')) {
      return true;
    }
    final combined = '${message ?? ''} ${error.toString()}'.toLowerCase();
    if (combined.contains('rate limit exceeded') ||
        combined.contains('spending cap reached') ||
        combined.contains('project not found')) {
      return true;
    }
    if (combined.contains('websocketconnectionclosed')) {
      return true;
    }
    if (combined.contains('cr: done') || combined.contains('cr:done')) {
      return true;
    }
    return false;
  }

  /// Issue title without stream connection ids or generated class names.
  static String? titleOf(ExceptionEvent event) {
    final fromException = ExceptionPayloadBuilder.shortName(event.exception);
    final raw = event.message?.trim();
    if (raw == null || raw.isEmpty) {
      return fromException;
    }
    final stripped = raw
        .replaceAll(_uuidInTitle, '<id>')
        .replaceFirst(RegExp(r'^Exception:\s+'), '')
        .trim();
    if (stripped.isEmpty || _isGeneratedClassTitle(stripped, event.exception)) {
      return fromException;
    }
    return stripped;
  }

  static bool _isGeneratedClassTitle(String value, Object error) {
    if (value.startsWith('Instance of ')) {
      return true;
    }
    // Stable names such as StateError stay. Generated `_FooImpl` does not.
    if (value.startsWith('_') || value.endsWith('Impl')) {
      return true;
    }
    final raw = error.runtimeType.toString();
    return value == raw && (raw.startsWith('_') || raw.endsWith('Impl'));
  }
}
