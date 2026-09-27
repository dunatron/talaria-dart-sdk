import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

void main() {
  const parser = UserAgentParser();

  test('parses Chrome on macOS desktop', () {
    const ua =
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/126.0.6478.127 Safari/537.36';
    final parsed = parser.parse(ua);
    expect(parsed.browserName, 'Chrome');
    expect(parsed.browserVersion, '126');
    expect(parsed.browserEngine, 'Blink');
    expect(parsed.osName, 'macOS');
    expect(parsed.device, 'desktop');
  });

  test('parses iPhone Safari as mobile', () {
    const ua =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 '
        'Safari/604.1';
    final parsed = parser.parse(ua);
    expect(parsed.browserName, 'Safari');
    expect(parsed.osName, 'iOS');
    expect(parsed.device, 'mobile');
    expect(parsed.browserEngine, 'WebKit');
  });

  test('empty UA returns no fields', () {
    final parsed = parser.parse('');
    expect(parsed.browserName, isNull);
    expect(parsed.device, isNull);
  });
}
