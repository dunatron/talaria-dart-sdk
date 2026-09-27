/// Compact UA parse for Flutter web / when the host forwards a browser UA.
///
/// Vocabulary matches the server parser: `device` is `mobile` / `tablet` /
/// `desktop`; browser version is the major segment only.
class ParsedUserAgent {
  const ParsedUserAgent({
    this.browserName,
    this.browserVersion,
    this.browserEngine,
    this.osName,
    this.osVersion,
    this.device,
  });

  final String? browserName;
  final String? browserVersion;
  final String? browserEngine;
  final String? osName;
  final String? osVersion;
  final String? device;
}

class UserAgentParser {
  const UserAgentParser();

  ParsedUserAgent parse(String? userAgent) {
    final ua = userAgent?.trim() ?? '';
    if (ua.isEmpty) {
      return const ParsedUserAgent();
    }
    final browser = _browser(ua);
    final os = _os(ua);
    return ParsedUserAgent(
      browserName: _unknownToNull(browser.name),
      browserVersion: _major(browser.version),
      browserEngine: _unknownToNull(_engine(ua)),
      osName: _unknownToNull(os.name),
      osVersion: _major(os.version),
      device: _device(ua),
    );
  }

  static String? _unknownToNull(String value) =>
      value.isEmpty || value == 'unknown' ? null : value;

  static String? _major(String version) {
    final match = RegExp(r'^(\d+)').firstMatch(version.trim());
    final major = match?.group(1);
    return (major == null || major.isEmpty) ? null : major;
  }

  ({String name, String version}) _browser(String ua) {
    final rules = <({String name, RegExp re})>[
      (name: 'Edge', re: RegExp(r'Edg(?:e|A|iOS)?/([\d.]+)')),
      (name: 'Opera', re: RegExp(r'OPR/([\d.]+)')),
      (name: 'Samsung Internet', re: RegExp(r'SamsungBrowser/([\d.]+)')),
      (name: 'Firefox', re: RegExp(r'Firefox/([\d.]+)')),
      (name: 'Chrome', re: RegExp(r'(?:Chrome|CriOS)/([\d.]+)')),
      (name: 'Safari', re: RegExp(r'Version/([\d.]+).*Safari')),
    ];
    for (final rule in rules) {
      final match = rule.re.firstMatch(ua);
      if (match != null) {
        return (name: rule.name, version: match.group(1) ?? '');
      }
    }
    return (name: 'unknown', version: '');
  }

  String _engine(String ua) {
    if (RegExp(r'Gecko/\d', caseSensitive: false).hasMatch(ua) &&
        ua.contains('Firefox/')) {
      return 'Gecko';
    }
    if (RegExp(r'(?:Chrome|CriOS|Edg|OPR|SamsungBrowser)/', caseSensitive: false)
        .hasMatch(ua)) {
      return 'Blink';
    }
    if (ua.contains('AppleWebKit')) {
      return 'WebKit';
    }
    return 'unknown';
  }

  ({String name, String version}) _os(String ua) {
    final win = RegExp(r'Windows NT ([\d.]+)').firstMatch(ua);
    if (win != null) {
      return (name: 'Windows', version: win.group(1) ?? '');
    }
    final android = RegExp(r'Android ([\d.]+)').firstMatch(ua);
    if (android != null) {
      return (name: 'Android', version: android.group(1) ?? '');
    }
    final ios = RegExp(r'(?:iPhone|iPad|iPod).*OS ([\d_]+)').firstMatch(ua);
    if (ios != null) {
      return (name: 'iOS', version: (ios.group(1) ?? '').replaceAll('_', '.'));
    }
    final mac = RegExp(r'Mac OS X ([\d_]+)').firstMatch(ua);
    if (mac != null) {
      return (name: 'macOS', version: (mac.group(1) ?? '').replaceAll('_', '.'));
    }
    if (ua.contains('CrOS')) {
      return (name: 'Chrome OS', version: '');
    }
    if (ua.contains('Linux')) {
      return (name: 'Linux', version: '');
    }
    return (name: 'unknown', version: '');
  }

  String _device(String ua) {
    if (RegExp(r'iPad|Tablet|Android(?!.*Mobile)', caseSensitive: false)
        .hasMatch(ua)) {
      return 'tablet';
    }
    if (RegExp(r'Mobi|iPhone|iPod|Android.*Mobile', caseSensitive: false)
        .hasMatch(ua)) {
      return 'mobile';
    }
    return 'desktop';
  }
}
