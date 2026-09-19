/// Sentry-style ignore matching: [String] is a substring, [RegExp] is a regex.
bool matchesIgnorePattern(String value, List<Pattern> patterns) {
  if (value.isEmpty || patterns.isEmpty) return false;
  for (final pattern in patterns) {
    if (pattern is String) {
      if (value.contains(pattern)) return true;
    } else if (pattern is RegExp) {
      if (pattern.hasMatch(value)) return true;
    } else if (pattern.allMatches(value).isNotEmpty) {
      return true;
    }
  }
  return false;
}

bool shouldDropEvent({
  required String message,
  String? stackTrace,
  required List<Pattern> ignoreErrors,
  required List<Pattern> ignoreUrls,
}) {
  if (matchesIgnorePattern(message, ignoreErrors)) return true;
  final stack = stackTrace ?? '';
  if (stack.isNotEmpty && matchesIgnorePattern(stack, ignoreUrls)) {
    return true;
  }
  return false;
}
