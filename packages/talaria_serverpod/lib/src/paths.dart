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

  /// Talaria SDK ingest and control calls, as Serverpod endpoint → methods.
  ///
  /// When an app reports to a Talaria server that is itself traced (Talaria
  /// dogfooding), tracing these feeds back: a rejected span batch triggers
  /// `sdk/reportDiscards`, which becomes a traced request, and so on.
  /// `replays` matches any `ingestSegment*` method. Dashboard methods on the
  /// same endpoints (flag management, heatmap viewing) stay traced, and so do
  /// an app's own endpoints that happen to share these names.
  static const sdkEndpointMethods = <String, Set<String>>{
    'events': {'ingest', 'ingestBatch'},
    'spans': {'ingestBatch'},
    'analytics': {'ingestBatch'},
    'heatmaps': {'ingestBatch', 'uploadSnapshot'},
    'screenHeatmaps': {'ingestBatch', 'uploadSnapshot', 'uploadRecording'},
    'replays': {'ingestSegment', 'ingestSegmentBatch'},
    'sdk': {'getConfig', 'reportDiscards'},
    'flags': {'evaluate', 'downloadDefinitions'},
  };

  /// True for a Talaria SDK ingest or control call ([sdkEndpointMethods]).
  static bool isSdkCall({required String endpoint, String? method}) {
    if (method == null || method.isEmpty) {
      return false;
    }
    if (endpoint == 'replays' && method.startsWith('ingestSegment')) {
      return true;
    }
    return sdkEndpointMethods[endpoint]?.contains(method) ?? false;
  }

  static bool isNoisy(Uri url) {
    final path = url.path;
    if (_isIngest(path)) {
      return true;
    }
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isNotEmpty &&
        isSdkCall(
          endpoint: segments.first,
          method: segments.length >= 2
              ? segments[1]
              : url.queryParameters['method'],
        )) {
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
    return isSdkCall(endpoint: endpoint, method: method);
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
