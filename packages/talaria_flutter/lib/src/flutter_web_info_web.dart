import 'package:web/web.dart' as web;

String? browserUserAgent() {
  try {
    final agent = web.window.navigator.userAgent;
    return agent.isEmpty ? null : agent;
  } catch (_) {
    return null;
  }
}

String? webRenderer() {
  try {
    final raw =
        web.document.documentElement?.getAttribute('flt-renderer') ?? '';
    if (raw.isEmpty) {
      return null;
    }
    final lower = raw.toLowerCase();
    if (lower.contains('skwasm')) {
      return 'skwasm';
    }
    if (lower.contains('canvaskit')) {
      return 'canvaskit';
    }
    if (lower.contains('html')) {
      return 'html';
    }
    return raw;
  } catch (_) {
    return null;
  }
}
