import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:talaria/talaria.dart';

import 'flutter_os_info_stub.dart'
    if (dart.library.io) 'flutter_os_info_io.dart' as os_info;
import 'flutter_web_info_stub.dart'
    if (dart.library.js_interop) 'flutter_web_info_web.dart' as web_info;

/// Flutter-only runtime tags / extra (web-safe — no `dart:io`).
class FlutterRuntime {
  FlutterRuntime._();

  static void enrich(TalariaClient client) {
    final locale = PlatformDispatcher.instance.locale.toLanguageTag();
    final os = _osName();
    final osVersion = os_info.operatingSystemVersion();
    final device = _deviceClass();
    final renderer = web_info.webRenderer();
    final userAgent = web_info.browserUserAgent();
    final timezone = web_info.browserTimeZone();
    final parsed = const UserAgentParser().parse(userAgent);

    client.setTags({
      'os': os,
      'locale': locale,
      if (device.isNotEmpty) 'device': device,
      if (renderer != null && renderer.isNotEmpty) 'flutter.renderer': renderer,
    });
    client.setExtra({
      'os': os,
      'locale': locale,
      if (device.isNotEmpty) 'device': device,
      if (renderer != null && renderer.isNotEmpty) 'renderer': renderer,
    });
    RuntimeContext.setLocale(locale);
    RuntimeContext.setOsName(os);
    RuntimeContext.setOsVersion(osVersion ?? parsed.osVersion);
    RuntimeContext.setDevice(device);
    if (timezone != null && timezone.isNotEmpty) {
      RuntimeContext.setTimezone(timezone);
    }
    if (userAgent != null && userAgent.isNotEmpty) {
      RuntimeContext.setUserAgent(userAgent);
    }
    if (kIsWeb) {
      RuntimeContext.setBrowserName(parsed.browserName);
      RuntimeContext.setBrowserVersion(parsed.browserVersion);
      RuntimeContext.setBrowserEngine(parsed.browserEngine);
      RuntimeContext.setOsName(parsed.osName ?? os);
      RuntimeContext.setOsVersion(parsed.osVersion ?? osVersion);
      RuntimeContext.setDevice(parsed.device ?? device);
    }
  }

  static String _osName() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.linux:
        return 'Linux';
      case TargetPlatform.fuchsia:
        return 'Fuchsia';
    }
  }

  static String _deviceClass() {
    final views = PlatformDispatcher.instance.views;
    if (views.isNotEmpty) {
      final view = views.first;
      final dpr = view.devicePixelRatio == 0 ? 1.0 : view.devicePixelRatio;
      final shortest = math.min(
            view.physicalSize.width,
            view.physicalSize.height,
          ) /
          dpr;
      if (shortest >= 1024) {
        return 'desktop';
      }
      if (shortest >= 600) {
        return 'tablet';
      }
      if (shortest > 0) {
        return 'mobile';
      }
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.android:
        return 'mobile';
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return 'desktop';
    }
  }
}
