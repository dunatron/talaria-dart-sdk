import 'package:talaria_serverpod/talaria_serverpod.dart';
import 'package:test/test.dart';

void main() {
  test('skips ingest, health, and insights', () {
    expect(
      TalariaServerpodPaths.isNoisy(
        Uri.parse('http://localhost:8080/events/ingestBatch'),
      ),
      isTrue,
    );
    expect(
      TalariaServerpodPaths.isNoisy(
        Uri.parse('http://localhost:8080/spans/ingestBatch'),
      ),
      isTrue,
    );
    expect(
      TalariaServerpodPaths.isNoisy(Uri.parse('http://localhost:8080/livez')),
      isTrue,
    );
    expect(
      TalariaServerpodPaths.isNoisy(
          Uri.parse('http://localhost:8080/insights')),
      isTrue,
    );
    expect(
      TalariaServerpodPaths.isNoisy(
        Uri.parse('http://localhost:8080/project/list'),
      ),
      isFalse,
    );
  });

  test('httpRoute prefers endpoint/method', () {
    expect(
      TalariaServerpodPaths.httpRoute(
        Uri.parse('http://localhost:8080/project/listProjects'),
      ),
      '/project/listProjects',
    );
    expect(
      TalariaServerpodPaths.httpRoute(
        Uri.parse('http://localhost:8080/project?method=listProjects'),
      ),
      '/project/listProjects',
    );
  });

  test('shouldSkipSession drops internals and ingest', () {
    expect(
      TalariaServerpodPaths.shouldSkipSession(endpoint: 'InternalSession'),
      isTrue,
    );
    expect(
      TalariaServerpodPaths.shouldSkipSession(endpoint: 'insights'),
      isTrue,
    );
    expect(
      TalariaServerpodPaths.shouldSkipSession(
        endpoint: 'events',
        method: 'ingestBatch',
      ),
      isTrue,
    );
    expect(
      TalariaServerpodPaths.shouldSkipSession(
        endpoint: 'project',
        method: 'listProjects',
      ),
      isFalse,
    );
  });
}
