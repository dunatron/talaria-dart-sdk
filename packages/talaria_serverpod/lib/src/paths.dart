/// Paths that must not become Talaria transactions (ingest loop + probes).
class TalariaServerpodPaths {
  TalariaServerpodPaths._();

  static const _health = {'/', '/livez', '/readyz', '/startupz'};

  static const _probes = {'/robots.txt', '/favicon.ico', '/sitemap.xml'};

  /// Talaria SDK ingest and control endpoints. Only /v1/ paths are used.
  static const sdkEndpoints = {
    'events',
    'spans',
    'analytics',
    'replays',
    'heatmaps',
    'screenHeatmaps',
    'sdk',
    'flags',
    'monitors',
  };

  /// True for a Talaria SDK ingest or control call (v1 paths only).
  static bool isSdkCall(Uri url) {
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();

    // Only /v1/<endpoint> paths (e.g., /v1/events, /v1/spans, /v1/monitors)
    for (var i = 0; i < segments.length - 1; i++) {
      if (segments[i] == 'v1' && sdkEndpoints.contains(segments[i + 1])) {
        return true;
      }
    }

    return false;
  }

  static bool isNoisy(Uri url) {
    if (isSdkCall(url)) {
      return true;
    }
    final normalized = _normalize(url.path);
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

  static bool shouldSkipSession({required String endpoint, String? method}) {
    if (endpoint == 'InternalSession' || endpoint == 'insights') {
      return true;
    }
    // Check if this is a v1 SDK path
    final testUri = Uri.parse('http://example.com/v1/$endpoint');
    return isSdkCall(testUri);
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
