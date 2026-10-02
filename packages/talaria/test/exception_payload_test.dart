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
    expect(
        StackFrameBuilder.isInApp('package:flutter/src/widgets.dart'), isFalse);
    expect(StackFrameBuilder.isInApp('package:my_app/main.dart'), isTrue);
    expect(StackFrameBuilder.isInApp('package:harbor_server/lab.dart'), isTrue);
    expect(StackFrameBuilder.isInApp('file:///tmp/main.dart'), isTrue);
    expect(
      StackFrameBuilder.isInApp('package:serverpod/serverpod.dart'),
      isFalse,
    );
    expect(
      StackFrameBuilder.isInApp('package:serverpod_auth/auth.dart'),
      isFalse,
    );
    expect(
      StackFrameBuilder.isInApp('package:relic_core/src/middleware.dart'),
      isFalse,
    );
    expect(
      StackFrameBuilder.isInApp(
        'package:talaria_serverpod/src/relic_middleware.dart',
      ),
      isFalse,
    );
    expect(StackFrameBuilder.isInApp('package:talaria/talaria.dart'), isFalse);
  });

  test('sanitizeTypeName strips private Impl suffixes', () {
    expect(
      ExceptionPayloadBuilder.sanitizeTypeName('_ApiUnauthorizedExceptionImpl'),
      'ApiUnauthorizedException',
    );
    expect(
      ExceptionPayloadBuilder.sanitizeTypeName(
        'package:foo._WebSocketConnectionClosedImpl',
      ),
      'WebSocketConnectionClosed',
    );
    expect(
        ExceptionPayloadBuilder.sanitizeTypeName('StateError'), 'StateError');
  });

  test('shortName prefers the exception message over a generated class', () {
    expect(
      ExceptionPayloadBuilder.shortName(_InvalidKeyException()),
      'Invalid API key',
    );
    expect(
      ExceptionPayloadBuilder.shortName(
        _StreamClosed('550e8400-e29b-41d4-a716-446655440000'),
      ),
      'Connection <id> closed',
    );
    expect(
      ExceptionPayloadBuilder.shortName(StateError('uncaught')),
      'Bad state: uncaught',
    );
    expect(ExceptionPayloadBuilder.shortName(TypeError()), 'TypeError');
    expect(
      ExceptionPayloadBuilder.shortName(FormatException('bad')),
      'bad',
    );
  });
}

class _InvalidKeyException implements Exception {
  @override
  String toString() => 'Invalid API key';
}

class _StreamClosed implements Exception {
  _StreamClosed(this.cid);

  final String cid;

  @override
  String toString() => 'Connection $cid closed';
}
