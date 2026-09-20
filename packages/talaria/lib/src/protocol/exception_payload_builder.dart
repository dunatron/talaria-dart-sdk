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

  static String shortName(Object error) => typeName(error);

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
