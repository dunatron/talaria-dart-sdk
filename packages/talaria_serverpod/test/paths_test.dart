import 'package:talaria_serverpod/talaria_serverpod.dart';
import 'package:test/test.dart';

void main() {
  test('skips v1 ingest paths, health, and insights', () {
    expect(
      TalariaServerpodPaths.isNoisy(
        Uri.parse('http://localhost:8080/v1/events'),
      ),
      isTrue,
    );
    expect(
      TalariaServerpodPaths.isNoisy(
        Uri.parse('http://localhost:8080/v1/spans'),
      ),
      isTrue,
    );
    expect(
      TalariaServerpodPaths.isNoisy(Uri.parse('http://localhost:8080/livez')),
      isTrue,
    );
    expect(
      TalariaServerpodPaths.isNoisy(
        Uri.parse('http://localhost:8080/insights'),
      ),
      isTrue,
    );
    expect(
      TalariaServerpodPaths.isNoisy(
        Uri.parse('http://localhost:8080/robots.txt'),
      ),
      isTrue,
    );
    expect(
      TalariaServerpodPaths.isNoisy(
        Uri.parse('http://localhost:8080/.well-known/oauth-protected-resource'),
      ),
      isTrue,
    );
    expect(
      TalariaServerpodPaths.isNoisy(
        Uri.parse('http://localhost:8080/project/list'),
      ),
      isFalse,
    );
    // Old paths are no longer noisy (hard cut)
    expect(
      TalariaServerpodPaths.isNoisy(
        Uri.parse('http://localhost:8080/events/ingestBatch'),
      ),
      isFalse,
    );
    expect(
      TalariaServerpodPaths.isNoisy(
        Uri.parse('http://localhost:8080/events/ingest'),
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

  test('shouldSkipSession drops internals and v1 SDK paths', () {
    expect(
      TalariaServerpodPaths.shouldSkipSession(endpoint: 'InternalSession'),
      isTrue,
    );
    expect(
      TalariaServerpodPaths.shouldSkipSession(endpoint: 'insights'),
      isTrue,
    );
    expect(TalariaServerpodPaths.shouldSkipSession(endpoint: 'events'), isTrue);
    expect(TalariaServerpodPaths.shouldSkipSession(endpoint: 'spans'), isTrue);
    expect(
      TalariaServerpodPaths.shouldSkipSession(
        endpoint: 'project',
        method: 'listProjects',
      ),
      isFalse,
    );
  });
}
