import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

void main() {
  group('Environment', () {
    test('aliases', () {
      expect(Environment.fromMixed('prod'), Environment.production);
      expect(Environment.fromMixed('live'), Environment.production);
      expect(Environment.fromMixed('uat'), Environment.staging);
      expect(Environment.fromMixed('test'), Environment.staging);
      expect(Environment.fromMixed('dev'), Environment.development);
      expect(Environment.fromMixed('local'), Environment.development);
      expect(Environment.fromMixed('production').wireValue, 'production');
    });
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
