/// Platform-specific bits for runtime enrichment (VM / native).
String? dartVersion() {
  // Avoid importing dart:io here — see io implementation.
  return null;
}

Map<String, String> platformTags() => const {};

Map<String, Object?> platformExtra() => const {};
