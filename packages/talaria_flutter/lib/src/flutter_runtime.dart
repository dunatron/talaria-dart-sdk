import 'package:flutter/foundation.dart';
import 'package:talaria/talaria.dart';

import 'flutter_web_info_stub.dart'
    if (dart.library.js_interop) 'flutter_web_info_web.dart' as web_info;

/// Flutter-only runtime tags / extra (web-safe — no `dart:io`).
class FlutterRuntime {
  FlutterRuntime._();

  static void enrich(TalariaClient client) {
    final locale = PlatformDispatcher.instance.locale.toLanguageTag();
    final os = defaultTargetPlatform.name;
    final renderer = web_info.webRenderer();
    final userAgent = web_info.browserUserAgent();
    final timezone = web_info.browserTimeZone();

    client.setTags({
      'os': os,
      'locale': locale,
      if (renderer != null && renderer.isNotEmpty) 'flutter.renderer': renderer,
    });
    client.setExtra({
      'os': os,
      'locale': locale,
      if (renderer != null && renderer.isNotEmpty) 'renderer': renderer,
    });
    RuntimeContext.setLocale(locale);
    if (timezone != null && timezone.isNotEmpty) {
      RuntimeContext.setTimezone(timezone);
    }
    if (userAgent != null && userAgent.isNotEmpty) {
      RuntimeContext.setUserAgent(userAgent);
    }
  }
}
