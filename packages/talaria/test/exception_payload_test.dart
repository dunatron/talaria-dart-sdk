import 'package:talaria/src/protocol/exception_payload_builder.dart';
import 'package:talaria/src/protocol/stack_frame_builder.dart';
import 'package:test/test.dart';

void main() {
  test('builds exception payload with frames oldest to newest', () {
    StackTrace? captured;
    try {
      throw StateError('nope');
    } catch (_, st) {
      captured = st;
    }

    final payload = ExceptionPayloadBuilder.fromError(
      StateError('nope'),
      captured,
    );

    expect(payload['__className__'], 'ExceptionDataDto');
    final values = payload['values'] as List;
    expect(values, isNotEmpty);
    final first = values.first as Map;
    expect(first['__className__'], 'ExceptionValueDto');
    expect(first['type'], contains('StateError'));
    final stacktrace = first['stacktrace'] as Map;
    final frames = stacktrace['frames'] as List;
    expect(frames, isNotEmpty);
    final frame = frames.last as Map;
    expect(frame['__className__'], 'StackFrameDto');
    expect(frame.containsKey('functionName') || frame.containsKey('absPath'),
        isTrue);
  });

  test('inApp heuristics', () {
    expect(StackFrameBuilder.isInApp('dart:core'), isFalse);
    expect(StackFrameBuilder.isInApp('package:flutter/src/widgets.dart'),
        isFalse);
    expect(StackFrameBuilder.isInApp('package:my_app/main.dart'), isTrue);
    expect(StackFrameBuilder.isInApp('file:///tmp/main.dart'), isTrue);
  });
}
