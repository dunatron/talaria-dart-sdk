import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

void main() {
  test('ring buffer drops oldest beyond 50', () {
    final buffer = BreadcrumbBuffer();
    for (var i = 0; i < 60; i++) {
      buffer.add(Breadcrumb(type: 'default', message: '$i'));
    }
    expect(buffer.length, 50);
    final messages = buffer.snapshot().map((b) => b.message).toList();
    expect(messages.first, '10');
    expect(messages.last, '59');
  });

  test('toWire includes BreadcrumbDto class name', () {
    final crumb = Breadcrumb(
      type: 'http',
      category: 'http',
      message: 'GET /x',
      level: 'info',
      data: {'http.request.method': 'GET'},
    );
    final wire = crumb.toWire();
    expect(wire['__className__'], 'BreadcrumbDto');
    expect(wire['type'], 'http');
    expect(wire['data'], {'http.request.method': 'GET'});
  });
}
