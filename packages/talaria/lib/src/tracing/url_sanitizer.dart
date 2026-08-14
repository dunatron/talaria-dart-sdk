/// Redact credentials and common secret query params from URLs.
class UrlSanitizer {
  UrlSanitizer._();

  static const _secretKeys = {
    'password',
    'passwd',
    'secret',
    'token',
    'api_key',
    'apikey',
    'access_token',
    'auth',
    'authorization',
  };

  static Uri sanitize(Uri uri) {
    var cleaned = uri.replace(userInfo: '');
    if (cleaned.hasQuery) {
      final params = Map<String, String>.from(cleaned.queryParameters);
      var changed = false;
      for (final key in params.keys.toList()) {
        if (_secretKeys.contains(key.toLowerCase())) {
          params[key] = '[Redacted]';
          changed = true;
        }
      }
      if (changed) {
        cleaned = cleaned.replace(queryParameters: params);
      }
    }
    return cleaned;
  }

  static String pathForName(Uri uri) {
    final path = uri.path;
    if (path.isEmpty) {
      return '/';
    }
    return path;
  }
}
