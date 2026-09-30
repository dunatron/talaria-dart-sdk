import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

void main() {
  test('ring buffer drops oldest beyond 50', () {
    final buffer = BreadcrumbBuffer();
    for (var i = 0; i < 60; i++) {
      buffer.add(Breadcrumb(type: 'default', message: '$i'));
    }
    expect(buffer.length, kMaxOtherBreadcrumbs);
    final messages = buffer.snapshot().map((b) => b.message).toList();
    expect(messages.first, '25');
    expect(messages.last, '59');
  });

  test('query crumbs do not evict application crumbs', () {
    final buffer = BreadcrumbBuffer();
    buffer.add(Breadcrumb(type: 'default', message: 'shopify.import_products'));
    for (var i = 0; i < 50; i++) {
      buffer.add(Breadcrumb(type: 'query', message: 'SELECT File $i'));
    }
    final messages = buffer.snapshot().map((b) => b.message).toList();
    expect(messages, contains('shopify.import_products'));
    expect(messages.length, kMaxQueryBreadcrumbs + 1);
    expect(messages[1], 'SELECT File 35');
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
