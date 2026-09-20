import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

void main() {
  group('IngestError.parse', () {
    test('reads __className__ and retry', () {
      final parsed = IngestError.parse(
        '{"__className__":"ApiUnauthorizedException","message":"Invalid API key","retry":false}',
      );
      expect(parsed.className, 'ApiUnauthorizedException');
      expect(parsed.message, 'Invalid API key');
      expect(parsed.retry, isFalse);
      expect(parsed.isPermanent, isTrue);
    });

    test('reads className compat key', () {
      final parsed = IngestError.parse(
        '{"className":"ApiNotFoundException","message":"Project not found"}',
      );
      expect(parsed.isPermanent, isTrue);
    });
  });

  group('IngestError.isPermanent', () {
    test('retry true is never permanent', () {
      const parsed = IngestError(
        className: 'ApiConflictException',
        message: 'quota exceeded',
        retry: true,
      );
      expect(parsed.isPermanent, isFalse);
    });

    test('inactive project is permanent without retry flag', () {
      const parsed = IngestError(
        className: 'ApiConflictException',
        message: 'Project is not active',
      );
      expect(parsed.isPermanent, isTrue);
    });

    test('5xx body is not permanent', () {
      const parsed = IngestError();
      expect(parsed.isPermanent, isFalse);
    });

    test('missing scope is scope-only', () {
      const parsed = IngestError(
        className: 'ApiUnauthorizedException',
        message: 'API key lacks required scope: spansWrite',
        retry: false,
      );
      expect(parsed.isPermanent, isTrue);
      expect(parsed.isScopeOnly, isTrue);
    });
  });
}
