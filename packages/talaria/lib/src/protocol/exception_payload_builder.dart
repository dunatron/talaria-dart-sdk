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
    if (error is Error || error is Exception) {
      return error.runtimeType.toString();
    }
    return error.runtimeType.toString();
  }

  static String shortName(Object error) {
    final full = typeName(error);
    final dot = full.lastIndexOf('.');
    return dot == -1 ? full : full.substring(dot + 1);
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
