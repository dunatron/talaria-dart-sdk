import 'dart:io' show Platform;

String? operatingSystemVersion() {
  try {
    final raw = Platform.operatingSystemVersion.trim();
    if (raw.isEmpty) {
      return null;
    }
    final match = RegExp(r'(\d+)').firstMatch(raw);
    return match?.group(1) ?? raw;
  } catch (_) {
    return null;
  }
}
