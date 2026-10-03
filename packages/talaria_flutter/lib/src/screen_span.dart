import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:talaria/talaria.dart';

import 'flutter_web_info_stub.dart'
    if (dart.library.js_interop) 'flutter_web_info_web.dart' as web_info;

/// Web `$pageview` follows the browser path, not every logical screen.
bool shouldEmitWebPageView({
  required bool isWeb,
  required String browserPath,
  required String? previousBrowserPath,
}) {
  if (!isWeb) {
    return false;
  }
  final path = browserPath.trim();
  if (path.isEmpty) {
    return false;
  }
  return path != previousBrowserPath;
}

/// Short INTERNAL page-load / screen span that finishes on the next idle frame.
///
/// A 10s cap prevents a shell route from becoming a multi-minute transaction.
/// When analytics is enabled, also emits `$screen`. On web, `$pageview` is
/// emitted only when the browser path changes.
class ScreenSpanController {
  ScreenSpanController({this.maxDuration = const Duration(seconds: 10)});

  /// Shared controller for [TalariaNavigatorObserver] and [TalariaFlutter.setScreen].
  static final ScreenSpanController instance = ScreenSpanController();

  final Duration maxDuration;

  Span? _span;
  Timer? _cap;
  int _generation = 0;
  String? _lastPagePath;

  Span? get current => _span;

  void start(String name, {TalariaClient? client, String? title}) {
    final label = name.trim();
    if (label.isEmpty) {
      return;
    }
    finish();

    RuntimeContext.setUrl(label);

    final resolved = client ?? Talaria.getClient();
    resolved?.setTags({
      'route': label,
      'screen': label,
    });
    resolved?.addBreadcrumb(Breadcrumb(
      type: 'navigation',
      category: 'navigation',
      message: label,
      data: {'ui.screen.name': label},
    ));

    _span = resolved?.startTransaction(
      label,
      kind: SpanKind.internal,
      attributes: {
        'ui.screen.name': label,
      },
    );
    final span = _span;
    if (span != null && span.isRecording) {
      RuntimeContext.setRequestId(span.spanId);
    }
    _emitAnalytics(label, resolved, title: title);
    _scheduleFinish();
  }

  void _emitAnalytics(String label, TalariaClient? client, {String? title}) {
    if (client == null || !client.analytics.isEnabled) {
      return;
    }
    final screenTitle =
        (title != null && title.trim().isNotEmpty) ? title.trim() : label;
    // ignore: discarded_futures
    client.analytics.screen(path: label, title: screenTitle);
    if (!kIsWeb) {
      return;
    }
    final page = web_info.browserPageContext();
    final browserPath = page?.path ?? label;
    if (!shouldEmitWebPageView(
      isWeb: true,
      browserPath: browserPath,
      previousBrowserPath: _lastPagePath,
    )) {
      return;
    }
    _lastPagePath = browserPath;
    // ignore: discarded_futures
    client.analytics.page(
      path: browserPath,
      url: page?.url,
      title: page?.title ?? screenTitle,
      referrer: page?.referrer,
    );
  }

  void _scheduleFinish() {
    final gen = ++_generation;
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      if (gen != _generation) {
        return;
      }
      finish();
    });
    _cap?.cancel();
    _cap = Timer(maxDuration, () {
      if (gen != _generation) {
        return;
      }
      finish();
    });
  }

  void finish() {
    _cap?.cancel();
    _cap = null;
    final span = _span;
    _span = null;
    if (span != null && span.isRecording) {
      span.setStatus(SpanStatus.ok);
      span.finish();
    }
  }
}
