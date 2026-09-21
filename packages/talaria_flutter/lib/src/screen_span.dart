import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:talaria/talaria.dart';

import 'flutter_web_info_stub.dart'
    if (dart.library.js_interop) 'flutter_web_info_web.dart' as web_info;

/// Short INTERNAL page-load / screen span that finishes on the next idle frame.
///
/// A 10s cap prevents a shell route from becoming a multi-minute transaction.
/// When analytics is enabled, also emits `$screen` (and `$pageview` on web).
class ScreenSpanController {
  ScreenSpanController({this.maxDuration = const Duration(seconds: 10)});

  /// Shared controller for [TalariaNavigatorObserver] and [TalariaFlutter.setScreen].
  static final ScreenSpanController instance = ScreenSpanController();

  final Duration maxDuration;

  Span? _span;
  Timer? _cap;
  int _generation = 0;

  Span? get current => _span;

  void start(String name, {TalariaClient? client}) {
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
    _emitAnalytics(label, resolved);
    _scheduleFinish();
  }

  void _emitAnalytics(String label, TalariaClient? client) {
    if (client == null || !client.analytics.isEnabled) {
      return;
    }
    // ignore: discarded_futures
    client.analytics.screen(path: label, title: label);
    if (kIsWeb) {
      final page = web_info.browserPageContext();
      // ignore: discarded_futures
      client.analytics.page(
        path: page?.path ?? label,
        url: page?.url,
        title: page?.title ?? label,
        referrer: page?.referrer,
      );
    }
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
