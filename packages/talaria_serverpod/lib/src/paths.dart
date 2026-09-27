/// Paths that must not become Talaria transactions (ingest loop + probes).
class TalariaServerpodPaths {
  TalariaServerpodPaths._();

  static const _health = {
    '/',
    '/livez',
    '/readyz',
    '/startupz',
  };

  static const _probes = {
    '/robots.txt',
    '/favicon.ico',
    '/sitemap.xml',
  };

  static bool isNoisy(Uri url) {
    final path = url.path;
    if (_isIngest(path)) {
      return true;
    }
    final normalized = _normalize(path);
    if (_health.contains(normalized) || _probes.contains(normalized)) {
      return true;
    }
    if (normalized == '/insights' || normalized.startsWith('/insights/')) {
      return true;
    }
    if (normalized.startsWith('/.well-known/')) {
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
    if (_isIngest(endpoint) || _isIngest(method ?? '')) {
      return true;
    }
    return false;
  }

  /// Batch and single-call ingest (`ingestBatch` and `ingest`).
  static bool _isIngest(String path) {
    return path.split(RegExp(r'[/?]')).any((segment) {
      return segment == 'ingest' || segment == 'ingestBatch';
    });
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
