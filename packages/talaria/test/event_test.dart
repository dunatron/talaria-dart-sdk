import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

void main() {
  test('Event.toWire includes className and required fields', () {
    final event = Event(
      message: 'boom',
      environment: Environment.production,
      level: SeverityLevel.error,
      title: 'StateError',
      platform: 'dart',
      tags: {'a': '1'},
      extraJson: '{"x":1}',
      exception: {
        '__className__': 'ExceptionDataDto',
        'values': <Object?>[],
      },
    );

    final wire = event.toWire();
    expect(wire['__className__'], 'IngestEventInput');
    expect(wire['message'], 'boom');
    expect(wire['environment'], 'production');
    expect(wire['level'], 'error');
    expect(wire['eventType'], 'error');
    expect(wire['platform'], 'dart');
    expect(wire['tags'], {'a': '1'});
    expect(wire['extraJson'], '{"x":1}');
    expect(wire['exception'], isA<Map<String, Object?>>());
  });

  test('empty message rejected', () {
    expect(
      () => Event(
        message: '  ',
        environment: Environment.development,
        level: SeverityLevel.info,
      ),
      throwsArgumentError,
    );
  });
}
