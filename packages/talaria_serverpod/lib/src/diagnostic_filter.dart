import 'package:serverpod/serverpod.dart';
import 'package:talaria/src/protocol/exception_payload_builder.dart';

import 'session_transaction.dart';

/// Expected Serverpod diagnostics that must not become Talaria Issues.
class DiagnosticFilter {
  DiagnosticFilter._();

  /// When set, rejected API calls are captured. Socket disconnects and the
  /// generic handler wrapper are still dropped.
  static bool captureRejectedRequests = false;

  static final _uuidInTitle = RegExp(
    r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
    caseSensitive: false,
  );

  static bool shouldDrop(ExceptionEvent event) {
    if (SessionTransaction.isGenericDiagnosticMessage(event.message)) {
      return true;
    }
    if (_isTransportNoise(event.exception, message: event.message)) {
      return true;
    }
    if (captureRejectedRequests) {
      return false;
    }
    return isExpectedException(event.exception, message: event.message);
  }

  static bool isExpectedException(Object error, {String? message}) {
    if (error is NotAuthorizedException) {
      return true;
    }
    final type = error.runtimeType.toString();
    if (type.contains('QuotaExceeded')) {
      return true;
    }
    if (type.contains('WebSocketConnectionClosed')) {
      return true;
    }
    if (_isTransportNoise(error, message: message)) {
      return true;
    }
    final combined = '${message ?? ''} ${error.toString()}'.toLowerCase();
    // Known client-credential noise. Unexpected unauthorized messages
    // (for example "Ingest requires an API key" on a dashboard RPC) stay.
    if (type.contains('ApiUnauthorizedException')) {
      return combined.contains('invalid api key') ||
          combined.contains('api key expired') ||
          combined.contains('project access denied');
    }
    if (combined.contains('rate limit exceeded') ||
        combined.contains('spending cap reached') ||
        combined.contains('project not found')) {
      return true;
    }
    return false;
  }

  static bool _isTransportNoise(Object error, {String? message}) {
    final type = error.runtimeType.toString();
    if (type.contains('WebSocketConnectionClosed')) {
      return true;
    }
    final combined = '${message ?? ''} ${error.toString()}'.toLowerCase();
    return combined.contains('websocketconnectionclosed') ||
        combined.contains('cr: done') ||
        combined.contains('cr:done');
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
