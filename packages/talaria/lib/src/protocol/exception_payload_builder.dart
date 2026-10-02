import '../capture_context.dart';
import 'stack_frame_builder.dart';

/// Builds Serverpod `ExceptionDataDto` wire trees from Dart errors.
class ExceptionPayloadBuilder {
  ExceptionPayloadBuilder._();

  static Map<String, Object?> fromError(
    Object error,
    StackTrace? stackTrace, {
    ExceptionMechanism? mechanism,
    String framePlatform = StackFrameBuilder.platform,
  }) {
    final mechanismWire = (mechanism ?? const ExceptionMechanism()).toWire();
    final frames = StackFrameBuilder.framesFromStackTrace(
      stackTrace,
      framePlatform: framePlatform,
    );

    final value = <String, Object?>{
      '__className__': 'ExceptionValueDto',
      'type': typeName(error),
      'value': messageOf(error),
      'mechanism': mechanismWire,
      'stacktrace': {
        '__className__': 'StackTraceDto',
        'frames': frames,
      },
    };

    return {
      '__className__': 'ExceptionDataDto',
      'values': [value],
    };
  }

  static String typeName(Object error) {
    return sanitizeTypeName(error.runtimeType.toString());
  }

  /// Strips private `_` prefixes and generated `Impl` suffixes.
  ///
  /// `_ApiUnauthorizedExceptionImpl` → `ApiUnauthorizedException`.
  static String sanitizeTypeName(String raw) {
    var name = raw.trim();
    final dot = name.lastIndexOf('.');
    if (dot != -1 && dot < name.length - 1) {
      name = name.substring(dot + 1);
    }
    if (name.startsWith('_')) {
      name = name.substring(1);
    }
    if (name.endsWith('Impl') && name.length > 4) {
      name = name.substring(0, name.length - 4);
    }
    return name;
  }

  static final _uuid = RegExp(
    r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
    caseSensitive: false,
  );

  /// Human title: the exception message, not a generated class name.
  ///
  /// `_ApiUnauthorizedExceptionImpl` whose `toString` is `Invalid API key`
  /// becomes `Invalid API key`. A bare type (`TypeError`, `Instance of …`)
  /// stays the sanitized type name. Stream connection ids become `<id>`.
  static String shortName(Object error) {
    final type = typeName(error);
    final human = _humanMessage(messageOf(error), error);
    if (human == null) {
      return type;
    }
    return human;
  }

  static String? _humanMessage(String raw, Object error) {
    var message = raw.trim();
    if (message.isEmpty) {
      return null;
    }
    message = message.replaceFirst(RegExp(r'^Exception:\s+'), '');
    final type = typeName(error);
    final rawType = error.runtimeType.toString();
    for (final head in {type, rawType, sanitizeTypeName(rawType)}) {
      final prefix = '$head: ';
      if (head.isNotEmpty && message.startsWith(prefix)) {
        message = message.substring(prefix.length).trim();
        break;
      }
    }
    message = message.replaceAll(_uuid, '<id>').trim();
    if (message.isEmpty || _isTypeDump(message, error)) {
      return null;
    }
    return message;
  }

  static bool _isTypeDump(String message, Object error) {
    if (message.startsWith('Instance of ')) {
      return true;
    }
    final raw = error.runtimeType.toString();
    if (message == raw || message == typeName(error)) {
      return true;
    }
    if (message.startsWith('_') && message.endsWith('Impl')) {
      return true;
    }
    return false;
  }

  static String messageOf(Object error) {
    if (error is Error) {
      final msg = error.toString();
      return msg.isEmpty ? error.runtimeType.toString() : msg;
    }
    if (error is Exception) {
      final msg = error.toString();
      // Exception.toString() often prefixes "Exception: "
      return msg.isEmpty ? error.runtimeType.toString() : msg;
    }
    return error.toString();
  }
}
