import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

void main() {
  group('IngestError.parse', () {
    test('reads problem+json invalid_key', () {
      final parsed = IngestError.parse(
        '{"type":"https://newtalaria.com/docs/reference/errors#invalid_key","title":"Invalid key","status":401,"detail":"Invalid API key","code":"invalid_key","requestId":"req_1"}',
      );
      expect(parsed.code, 'invalid_key');
      expect(parsed.message, 'Invalid API key');
      expect(parsed.retry, isFalse);
      expect(parsed.requestId, 'req_1');
      expect(parsed.isPermanent, isTrue);
      expect(parsed.isGlobalCredentialFailure, isTrue);
    });

    test('reads wrong_cell extensions', () {
      final parsed = IngestError.parse(
        '{"status":421,"code":"wrong_cell","detail":"Wrong cell","cell":"eu1","url":"https://ingest-eu1.newtalaria.com","requestId":"req_2"}',
      );
      expect(parsed.cell, 'eu1');
      expect(parsed.cellUrl, 'https://ingest-eu1.newtalaria.com');
      expect(parsed.isPermanent, isTrue);
    });

    test('insufficient_scope is scope-only', () {
      final parsed = IngestError.parse(
        '{"status":403,"code":"insufficient_scope","detail":"Missing events:write"}',
      );
      expect(parsed.isPermanent, isTrue);
      expect(parsed.isScopeOnly, isTrue);
      expect(parsed.isGlobalCredentialFailure, isFalse);
    });

    test('rate_limited is not permanent', () {
      final parsed = IngestError.parse(
        '{"status":429,"code":"rate_limited","detail":"Slow down"}',
      );
      expect(parsed.isPermanent, isFalse);
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

    test('ingest_blocked is not permanent', () {
      final parsed = IngestError.parse(
        '{"status":402,"code":"ingest_blocked","reason":"org_unpaid","retryAfterSeconds":900,"detail":"Ingest is stopped for this organisation."}',
      );
      expect(parsed.retry, isTrue);
      expect(parsed.isPermanent, isFalse);
      expect(parsed.isIngestBlocked, isTrue);
      expect(parsed.reason, 'org_unpaid');
      expect(parsed.retryAfterSeconds, 900);
    });

    test('forbidden_origin is permanent', () {
      final parsed = IngestError.parse(
        '{"status":403,"code":"forbidden_origin","detail":"Origin is not allowed"}',
      );
      expect(parsed.retry, isFalse);
      expect(parsed.isPermanent, isTrue);
      expect(parsed.isForbiddenOrigin, isTrue);
      expect(parsed.isIngestBlocked, isFalse);
    });
  });

  group('IngestProblemCode', () {
    test('wire names and tryParse are exhaustive and closed', () {
      expect(IngestProblemCode.ingestBlocked.wire, 'ingest_blocked');
      expect(IngestProblemCode.tryParse('ingest_blocked'),
          IngestProblemCode.ingestBlocked);
      expect(IngestProblemCode.tryParse('unknown_code'), isNull);
      expect(IngestProblemCode.values.length, 11);
    });

    test('clampRetryAfter is 15 minutes to 24 hours', () {
      expect(IngestProblemCode.clampRetryAfter(null), 15 * 60);
      expect(IngestProblemCode.clampRetryAfter(60), 15 * 60);
      expect(IngestProblemCode.clampRetryAfter(3600), 3600);
      expect(IngestProblemCode.clampRetryAfter(48 * 60 * 60), 24 * 60 * 60);
    });
  });
}
