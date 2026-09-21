import 'package:talaria/talaria.dart';
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

AnalyticsPageContext? browserPageContext() {
  try {
    final loc = web.window.location;
    final href = loc.href;
    final path = loc.pathname;
    final title = web.document.title;
    final referrer = web.document.referrer;
    return AnalyticsPageContext(
      url: href.isEmpty ? null : href,
      path: path.isEmpty ? null : path,
      title: title.isEmpty ? null : title,
      referrer: referrer.isEmpty ? null : referrer,
    );
  } catch (_) {
    return null;
  }
}
