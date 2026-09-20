/// Paths that must not become Talaria transactions (ingest loop + probes).
class TalariaServerpodPaths {
  TalariaServerpodPaths._();

  static const _health = {
    '/',
    '/livez',
    '/readyz',
    '/startupz',
  };

  static bool isNoisy(Uri url) {
    final path = url.path;
    if (path.contains('ingestBatch')) {
      return true;
    }
    final normalized = _normalize(path);
    if (_health.contains(normalized)) {
      return true;
    }
    if (normalized == '/insights' || normalized.startsWith('/insights/')) {
      return true;
    }
    return false;
  }

  static bool shouldSkipSession({
    required String endpoint,
    String? method,
  }) {
    if (endpoint == 'InternalSession' || endpoint == 'insights') {
      return true;
    }
    if (endpoint.contains('ingestBatch') ||
        (method?.contains('ingestBatch') ?? false)) {
      return true;
    }
    return false;
  }

  static String httpRoute(Uri url) {
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    final queryMethod = url.queryParameters['method'];
    if (segments.length >= 2) {
      return '/${segments[0]}/${segments[1]}';
    }
    if (segments.isNotEmpty && queryMethod != null && queryMethod.isNotEmpty) {
      return '/${segments.first}/$queryMethod';
    }
    if (segments.isNotEmpty) {
      return '/${segments.first}';
    }
    final path = url.path;
    return path.isEmpty ? '/' : path;
  }

  static String _normalize(String path) {
    if (path.isEmpty) {
      return '/';
    }
    if (path.length > 1 && path.endsWith('/')) {
      return path.substring(0, path.length - 1);
    }
    return path;
  }
}
