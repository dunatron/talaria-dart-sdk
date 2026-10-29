import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

void main() {
  test('init derives the ingest host from the key cell', () {
    final options = TalariaOptions(
      apiKey:
          'tal_sk_test_nz1_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg3B299S',
      release: '1.4.2',
      minLevel: SeverityLevel.warning,
    );
    expect(options.url, 'https://ingest-nz1.newtalaria.com');
    expect(options.release, '1.4.2');
    expect(options.minLevel, SeverityLevel.warning);
  });

  test('a 0.3.6 environment argument is accepted and not stored', () {
    final options = TalariaOptions(
      url: 'https://ingest.newtalaria.com',
      apiKey:
          'tal_sk_test_nz1_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg3B299S',
      environment: 'production',
    );
    expect(options.apiKey,
        'tal_sk_test_nz1_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg3B299S');
  });

  group('SeverityLevel', () {
    test('aliases and ranks', () {
      expect(SeverityLevel.tryFromMixed('warn'), SeverityLevel.warning);
      expect(SeverityLevel.tryFromMixed('critical'), SeverityLevel.fatal);
      expect(SeverityLevel.error.atLeast(SeverityLevel.warning), isTrue);
      expect(SeverityLevel.info.atLeast(SeverityLevel.warning), isFalse);
      expect(
        SeverityLevel.max(SeverityLevel.info, SeverityLevel.error),
        SeverityLevel.error,
      );
      expect(SeverityLevel.fatal.toEventType(), 'error');
    });
  });
}
