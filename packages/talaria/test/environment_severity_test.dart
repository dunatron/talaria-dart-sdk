import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

void main() {
  test('README init omits environment', () {
    final options = TalariaOptions(
      dsn: 'https://ingest.newtalaria.com',
      apiKey: 'tal_live_readme_sample',
      release: '1.4.2',
      minLevel: SeverityLevel.warning,
    );
    expect(options.baseUrl, 'https://ingest.newtalaria.com');
    expect(options.apiKey, 'tal_live_readme_sample');
    expect(options.release, '1.4.2');
    expect(options.minLevel, SeverityLevel.warning);
  });

  test('a 0.3.6 environment argument is accepted and not stored', () {
    final options = TalariaOptions(
      dsn: 'https://ingest.newtalaria.com',
      apiKey: 'tal_live_readme_sample',
      environment: 'production',
    );
    expect(options.apiKey, 'tal_live_readme_sample');
  });

  group('SeverityLevel', () {
    test('aliases and ranks', () {
      expect(SeverityLevel.tryFromMixed('warn'), SeverityLevel.warning);
      expect(SeverityLevel.tryFromMixed('critical'), SeverityLevel.fatal);
      expect(SeverityLevel.error.atLeast(SeverityLevel.warning), isTrue);
      expect(SeverityLevel.info.atLeast(SeverityLevel.warning), isFalse);
      expect(SeverityLevel.max(SeverityLevel.info, SeverityLevel.error),
          SeverityLevel.error);
      expect(SeverityLevel.fatal.toEventType(), 'error');
    });
  });
}
