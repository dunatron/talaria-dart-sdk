import 'package:talaria/talaria.dart';
import 'package:talaria_serverpod/src/session_spans.dart';
import 'package:test/test.dart';

void main() {
  test('names FutureCall sessions as consumer transactions', () {
    expect(
      SessionSpans.nameFor(
        endpoint: 'FutureCall',
        method: 'evaluateAlerts',
        futureCallName: 'evaluateAlerts',
      ),
      'FutureCall.evaluateAlerts',
    );
    expect(SessionSpans.kindFor(isFutureCall: true), SpanKind.consumer);
  });

  test('names method sessions as endpoint/method', () {
    expect(
      SessionSpans.nameFor(
        endpoint: 'project',
        method: 'listProjects',
      ),
      'project/listProjects',
    );
    expect(SessionSpans.kindFor(isFutureCall: false), SpanKind.server);
    expect(
      SessionSpans.attributesFor(
        endpoint: 'project',
        method: 'listProjects',
      )['http.route'],
      '/project/listProjects',
    );
  });
}
