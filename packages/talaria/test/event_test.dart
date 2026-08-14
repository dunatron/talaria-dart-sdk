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

  test('Event.toWire includes traceId spanId breadcrumbs', () {
    final event = Event(
      message: 'boom',
      environment: Environment.production,
      level: SeverityLevel.error,
      traceId: '0af7651916cd43dd8448eb211c80319c',
      spanId: 'b7ad6b7169203331',
      breadcrumbs: [
        {
          '__className__': 'BreadcrumbDto',
          'timestamp': '2026-01-01T00:00:00.000Z',
          'type': 'http',
        },
      ],
    );
    final wire = event.toWire();
    expect(wire['traceId'], '0af7651916cd43dd8448eb211c80319c');
    expect(wire['spanId'], 'b7ad6b7169203331');
    expect(wire['breadcrumbs'], hasLength(1));
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
