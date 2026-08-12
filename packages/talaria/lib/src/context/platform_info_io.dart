import 'dart:io' show Platform;

String? dartVersion() {
  try {
    return Platform.version.split(' ').first;
  } catch (_) {
    return null;
  }
}

Map<String, String> platformTags() {
  final tags = <String, String>{};
  try {
    tags['os'] = Platform.operatingSystem;
  } catch (_) {}
  final version = dartVersion();
  if (version != null) {
    tags['dart.version'] = version;
  }
  return tags;
}

Map<String, Object?> platformExtra() {
  final extra = <String, Object?>{};
  try {
    extra['dart_version'] = Platform.version;
    extra['hostname'] = Platform.localHostname;
    extra['number_of_processors'] = Platform.numberOfProcessors;
  } catch (_) {}
  return extra;
}
