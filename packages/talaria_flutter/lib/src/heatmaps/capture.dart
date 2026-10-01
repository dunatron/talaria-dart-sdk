import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:talaria/talaria.dart';

import 'classifier.dart';
import 'heatmap_tree.dart';
import 'markers.dart';
import 'privacy.dart';
import 'scroll_tracker.dart';
import 'session.dart';

/// Captures taps, scroll depth, and an on-request fold snapshot for heatmaps.
///
/// Continuous work is signals only (no periodic screenshots, no scroll
/// scrubbing). When the server asks for a snapshot, one idle fold PNG plus a
/// structural tree upload after settle. While waiting, tiles may be captured
/// when the user naturally rests deeper in a scroll. Rage / dead / error taps
/// may take up to three event-driven micro-frames (not a continuous filmstrip).
///
/// [privacy] controls which regions are covered on the rare PNG. Inputs, text,
/// and images stay visible unless you opt in. Password fields are covered
/// either way.
class TalariaScreenCapture extends StatefulWidget {
  const TalariaScreenCapture({
    super.key,
    required this.child,
    this.privacy = const TalariaHeatmapPrivacy(),
  });

  final Widget child;
  final TalariaHeatmapPrivacy privacy;

  @override
  State<TalariaScreenCapture> createState() => _TalariaScreenCaptureState();
}

class _TalariaScreenCaptureState extends State<TalariaScreenCapture>
    with WidgetsBindingObserver {
  final _boundaryKey = GlobalKey();
  final _session = ScreenHeatmapSession();
  Timer? _flush;
  Timer? _settle;
  Timer? _scrollRest;
  var _flushing = false;
  var _capturing = false;
  var _snapshotPending = false;
  var _microFraming = false;
  final _snapshotSent = <String>{};
  final _recordingSent = <String>{};
  Offset? _down;
  String? _routePath;
  String? _observedRoute;
  var _manualScreen = false;
  var _background = false;
  var _flushHooked = false;
  var _openScheduled = false;
  int? _fingerprintHash;
  var _fingerprintScheduled = false;
  String _deviceClassName = 'mobile';
  String _orientationName = 'portrait';
  var _keyboardOpen = false;
  DateTime _lastInteraction = DateTime.fromMillisecondsSinceEpoch(0);
  Rect? _scrollport;

  static const _settleDelay = Duration(seconds: 2);
  static const _scrollRestDelay = Duration(milliseconds: 450);
  static const _maxPngBytes = 500 * 1024;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ScreenHeatmapController.instance.session = _session;
    ScreenHeatmapController.instance.listenScreen(_onManualScreen);
    ScreenHeatmapController.instance.listenRoute(_onObservedRoute);
    FocusManager.instance.addListener(_onFocus);
    _session.onInterestingTap = (_) {
      unawaited(_captureMicroFrames());
    };
    _flush = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_tick());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = Router.maybeOf(context)?.routeInformationProvider;
    provider?.removeListener(_onRoute);
    provider?.addListener(_onRoute);
    unawaited(_syncRoute());
  }

  @override
  void dispose() {
    Router.maybeOf(context)?.routeInformationProvider?.removeListener(_onRoute);
    WidgetsBinding.instance.removeObserver(this);
    _flush?.cancel();
    _settle?.cancel();
    _scrollRest?.cancel();
    _session.onInterestingTap = null;
    ScreenHeatmapController.instance.unlistenScreen(_onManualScreen);
    ScreenHeatmapController.instance.unlistenRoute(_onObservedRoute);
    FocusManager.instance.removeListener(_onFocus);
    ScreenHeatmapController.instance.client?.removeBeforeFlush(_onClientFlush);
    if (ScreenHeatmapController.instance.session == _session) {
      ScreenHeatmapController.instance.session = null;
    }
    unawaited(_flushSession());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final hidden = screenHeatmapAppIsHidden(state);
    final wasHidden = _background;
    _background = hidden;
    if (wasHidden && !hidden) unawaited(_syncRoute());
  }

  void _noteInteraction() {
    _lastInteraction = DateTime.now();
    if (_snapshotPending) _armSettle();
  }

  void _onManualScreen(String name) {
    _manualScreen = true;
    unawaited(_open(name));
  }

  void _onObservedRoute(String name) {
    if (_routePath != null || _manualScreen) return;
    if (name == _observedRoute) return;
    _observedRoute = name;
    unawaited(_open(name));
  }

  void _onFocus() {
    _session.classifier.noteEffect(DateTime.now().millisecondsSinceEpoch);
    _noteInteraction();
  }

  Future<void> _onClientFlush() => _flushSession();

  void _onRoute() {
    unawaited(_syncRoute());
  }

  /// Opens a screen view once policy allows it.
  ///
  /// [MaterialApp.builder] sits above the [Router], so [Router.maybeOf] is
  /// null for the usual install. The screen name then comes from
  /// [TalariaFlutter.setScreen] or the navigator observer. Policy often
  /// arrives after that first name, so this retries until the session opens.
  Future<void> _syncRoute() async {
    if (!mounted) return;
    final router = Router.maybeOf(context);
    final config = router?.routerDelegate.currentConfiguration;
    final fromDelegate = config is RouteInformation ? config.uri.path : null;
    final fromProvider = router?.routeInformationProvider?.value.uri.path;
    final path = (fromDelegate != null && fromDelegate.isNotEmpty)
        ? fromDelegate
        : fromProvider;
    if (path != null && path.isNotEmpty && path != _routePath) {
      _routePath = path;
      _manualScreen = false;
      ScreenHeatmapController.instance.manualScreen = null;
    }
    final key = _screenKey;
    if (key == null || key.isEmpty) return;
    await _open(key);
  }

  Future<void> _tick() async {
    await _syncRoute();
    await _flushSession();
  }

  Future<void> _open(String key) async {
    if (!ScreenHeatmapController.instance.captureEnabled || _background) return;
    if (_session.isOpen && _session.screenKey == key) return;
    if (_session.isOpen) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _session.classifier.noteEffect(now);
      _session.classifier.flushAll(now);
      await _flushSession();
    }
    if (!mounted) return;
    final box = context.findRenderObject();
    final size = box is RenderBox && box.hasSize ? box.size : const Size(1, 1);
    _session.open(
      screenKey: key,
      nowMs: DateTime.now().millisecondsSinceEpoch,
      viewportWidth: size.width.round(),
      viewportHeight: size.height.round(),
    );
    _snapshotPending = false;
    _settle?.cancel();
  }

  void _onPointerDown(PointerDownEvent event) {
    _down = event.position;
    _noteInteraction();
  }

  void _onPointerUp(PointerUpEvent event) {
    final start = _down;
    _down = null;
    _noteInteraction();
    if (start == null) return;
    if ((event.position - start).distance > 18) return;
    if (!ScreenHeatmapController.instance.captureEnabled || _background) return;
    final key = _screenKey;
    if (key == null || key.isEmpty) return;
    if (!_session.isOpen) unawaited(_open(key));
    final root = _boundaryKey.currentContext as Element?;
    final boundary = _boundaryKey.currentContext?.findRenderObject();
    if (root == null || boundary is! RenderBox || !boundary.hasSize) return;
    final hit =
        collectHeatmapTree(root, boundary, includeText: false).hit(event.position);
    if (hit == null) return;
    final local = boundary.globalToLocal(event.position);
    final metrics = _session.scroll.state;
    final horizontal = metrics?.axis == ScreenScrollAxis.horizontal;
    final contentX =
        (horizontal ? (metrics?.offsetPx ?? 0) + local.dx : local.dx).round();
    final contentY =
        (horizontal ? local.dy : (metrics?.offsetPx ?? 0) + local.dy).round();
    final inside = event.position - hit.globalRect.topLeft;
    _session.classifier.add(
      TapSample(
        path: hit.path,
        role: hit.role,
        relX: toBasisPoints(inside.dx, hit.globalRect.width),
        relY: toBasisPoints(inside.dy, hit.globalRect.height),
        xBp: toBasisPoints(local.dx, boundary.size.width),
        yBp: toBasisPoints(local.dy, boundary.size.height),
        contentX: contentX < 0 ? 0 : contentX,
        contentY: contentY < 0 ? 0 : contentY,
        clientX: local.dx,
        clientY: local.dy,
        deadEligible: hit.deadEligible && !_textSelectionActive(),
      ),
      DateTime.now().millisecondsSinceEpoch,
    );
    _scheduleFingerprint();
  }

  bool _textSelectionActive() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    final editor = focusContext.findAncestorStateOfType<EditableTextState>();
    if (editor == null) return false;
    final selection = editor.textEditingValue.selection;
    return selection.isValid && !selection.isCollapsed;
  }

  String? get _screenKey {
    final manual = ScreenHeatmapController.instance.manualScreen;
    if (manual != null && manual.isNotEmpty) return manual;
    return _routePath ?? _observedRoute;
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis == Axis.horizontal &&
        notification.metrics.viewportDimension < 200) {
      return false;
    }
    final box = context.findRenderObject();
    final size = box is RenderBox && box.hasSize ? box.size : Size.zero;
    final vertical = notification.metrics.axis == Axis.vertical;
    final area = notification.metrics.viewportDimension *
        (vertical ? size.width : size.height);
    final current = _session.scroll.state;
    final bestArea = current == null
        ? 0.0
        : (current.axis == ScreenScrollAxis.vertical
                ? current.viewportHeight
                : current.viewportWidth)
            .toDouble();
    if (!isPrimaryScroll(
      viewportArea: area,
      bestArea: bestArea,
      vertical: vertical,
      bestVertical: current?.axis != ScreenScrollAxis.horizontal,
    )) {
      return false;
    }
    final moved = notification is ScrollUpdateNotification &&
        (notification.scrollDelta?.abs() ?? 0) > 1;
    if (moved) {
      _session.classifier.noteEffect(DateTime.now().millisecondsSinceEpoch);
      _noteInteraction();
      _scrollRest?.cancel();
    }
    _session.scroll.update(
      viewportWidth: size.width.round(),
      viewportHeight: size.height.round(),
      pixels: notification.metrics.pixels,
      maxScrollExtent: notification.metrics.maxScrollExtent,
      viewportDimension: notification.metrics.viewportDimension,
      vertical: vertical,
    );
    final scrollable = notification.context
        ?.findAncestorStateOfType<ScrollableState>();
    final boundary = _boundaryKey.currentContext?.findRenderObject();
    if (scrollable != null &&
        boundary is RenderBox &&
        boundary.hasSize) {
      _scrollport = _scrollportOf(boundary, scrollable);
    }
    final settled = notification is ScrollEndNotification ||
        (notification is UserScrollNotification &&
            notification.direction == ScrollDirection.idle);
    if (settled) _armScrollRest();
    return false;
  }

  void _armScrollRest() {
    _scrollRest?.cancel();
    _scrollRest = Timer(_scrollRestDelay, () {
      unawaited(_captureOpportunisticTile());
    });
  }

  /// Capture the current viewport as a tile when the user rested past the fold.
  /// Never teleports the scroll position.
  Future<void> _captureOpportunisticTile() async {
    if (_background || !ScreenHeatmapController.instance.captureEnabled) return;
    if (!_session.isOpen || _capturing) return;
    final metrics = _session.scroll.state;
    if (metrics == null) return;
    final viewport = metrics.axis == ScreenScrollAxis.horizontal
        ? metrics.viewportWidth
        : metrics.viewportHeight;
    if (viewport <= 1) return;
    final offset = metrics.offsetPx;
    if (offset < viewport ~/ 2) return;
    // Bucket to viewport steps so nearby rests share one tile.
    final bucket = (offset ~/ viewport) * viewport;
    if (bucket <= 0 || _session.tiles.containsKey(bucket)) return;
    if (_session.tiles.length >= 8) return;
    final png = await _captureFoldPng(crop: _scrollport);
    if (png == null) return;
    _session.addTile(bucket, png);
  }

  /// Up to three frames around a rage / dead / error tap — not a 1Hz loop.
  Future<void> _captureMicroFrames() async {
    if (_microFraming || _background) return;
    if (!ScreenHeatmapController.instance.captureEnabled) return;
    if (!_session.isOpen) return;
    _microFraming = true;
    try {
      for (var i = 0; i < 3; i++) {
        if (!mounted || !_session.isOpen) break;
        final png = await _captureFoldPng();
        if (png != null) {
          _session.addFrame(
            png,
            DateTime.now().millisecondsSinceEpoch - _session.startedAtMs,
          );
        }
        if (i < 2) await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    } finally {
      _microFraming = false;
    }
  }

  Future<void> _flushSession() async {
    if (_flushing) return;
    if (!ScreenHeatmapController.instance.captureEnabled) return;
    final client =
        ScreenHeatmapController.instance.client ?? Talaria.getClient();
    if (client == null || !_session.isOpen) return;
    _flushing = true;
    try {
      await _flushOpenSession(client);
    } catch (_) {
    } finally {
      _flushing = false;
    }
  }

  Future<void> _flushOpenSession(TalariaClient client) async {
    _session.classifier.tick(DateTime.now().millisecondsSinceEpoch);
    if (!_session.shouldSend(
      deviceClass: _deviceClassName,
      orientation: _orientationName,
      keyboard: _keyboardOpen,
    )) {
      return;
    }
    final throughTap = _session.unsentTapEnd;
    final view = _session.toView(
      anonymousId: client.anonymousId,
      sessionId: client.sessionId,
      userId: client.userId,
      release: client.options.release,
      osName: null,
      deviceClass: _deviceClassName,
      orientation: _orientationName,
      keyboard: _keyboardOpen,
      replayId: RuntimeContext.replayId,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (view == null) return;
    try {
      final response = await client.sendScreenHeatmapBatch([view]);
      if (response['enabled'] == false) {
        client.options.heatmapsEnabled = false;
        return;
      }
      _session.markSent(
        throughTap: throughTap,
        deviceClass: _deviceClassName,
        orientation: _orientationName,
        keyboard: _keyboardOpen,
      );
      final requests = response['snapshotRequests'];
      final id = _session.screenViewId;
      final requested = id != null && requests is List && requests.contains(id);
      if (requested &&
          !_snapshotSent.contains(id) &&
          _session.screenKey == _screenKey) {
        _snapshotPending = true;
        _armSettle();
      }
      if (_session.wantsRecording) {
        final recordingId = _session.recordingId;
        if (recordingId != null && !_recordingSent.contains(recordingId)) {
          final recording = _session.recordingInput();
          if (recording != null) {
            await client.uploadScreenHeatmapRecording(recording);
            _recordingSent.add(recordingId);
          }
        }
      }
    } catch (_) {}
  }

  void _armSettle() {
    _settle?.cancel();
    final elapsed = DateTime.now().difference(_lastInteraction);
    final wait = elapsed >= _settleDelay
        ? Duration.zero
        : _settleDelay - elapsed;
    _settle = Timer(wait, () {
      unawaited(_uploadIdleSnapshot());
    });
  }

  Future<void> _uploadIdleSnapshot() async {
    if (!_snapshotPending || !mounted) return;
    if (_background || !ScreenHeatmapController.instance.captureEnabled) return;
    final id = _session.screenViewId;
    if (id == null || _snapshotSent.contains(id)) {
      _snapshotPending = false;
      return;
    }
    if (DateTime.now().difference(_lastInteraction) < _settleDelay) {
      _armSettle();
      return;
    }
    final client =
        ScreenHeatmapController.instance.client ?? Talaria.getClient();
    if (client == null) return;
    await _nextFrame();
    if (!mounted || _session.screenViewId != id) return;
    final manifest = _manifestJson();
    final png = await _captureFoldPng();
    if (!mounted || _session.screenViewId != id) return;
    final input = _session.snapshotInput(
      png: png ?? const <int>[],
      manifestJson: manifest,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (input == null) return;
    try {
      await client.uploadScreenHeatmapSnapshot(input);
      _snapshotSent.add(id);
      _snapshotPending = false;
    } catch (_) {
      // Retry on next settle if still pending.
      _armSettle();
    }
  }

  void _scheduleFingerprint() {
    if (_fingerprintScheduled || _session.classifier.pendingCount == 0) return;
    _fingerprintScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fingerprintScheduled = false;
      if (!mounted) return;
      final next = _fingerprint();
      if (_fingerprintHash != null && next != _fingerprintHash) {
        _session.classifier.noteEffect(DateTime.now().millisecondsSinceEpoch);
      }
      _fingerprintHash = next;
      if (_session.classifier.pendingCount > 0) _scheduleFingerprint();
    });
  }

  int _fingerprint() {
    final root = _boundaryKey.currentContext as Element?;
    if (root == null) return 0;
    var hash = 0;
    void visit(Element element) {
      final widget = element.widget;
      if (widget is Semantics ||
          widget is TalariaHeatmapAnchor ||
          widget is TalariaMask ||
          widget is EditableText) {
        final box = element.renderObject;
        if (box is RenderBox && box.hasSize && box.attached) {
          final rect = box.localToGlobal(Offset.zero) & box.size;
          hash = Object.hash(
            hash,
            widget.runtimeType,
            rect.left.round(),
            rect.top.round(),
            rect.width.round(),
            rect.height.round(),
            widget is Semantics ? widget.properties.label : null,
            widget is Semantics ? widget.properties.identifier : null,
          );
        }
      }
      element.visitChildren(visit);
    }

    visit(root);
    return hash;
  }

  String _manifestJson() {
    final boundary = _boundaryKey.currentContext?.findRenderObject();
    final root = _boundaryKey.currentContext as Element?;
    if (boundary is! RenderBox || !boundary.hasSize || root == null) {
      return '{"v":1,"nodes":[]}';
    }
    final metrics = _session.scroll.state;
    final items = <String>[];
    for (final node in collectHeatmapTree(root, boundary, includeText: true)
        .forManifest(boundary.size)) {
      if (items.length >= 200) break;
      final local = node.localRect;
      final xBp = toBasisPoints(local.left, boundary.size.width);
      final yBp = toBasisPoints(local.top, boundary.size.height);
      final wBp = toBasisPoints(local.width, boundary.size.width);
      final hBp = toBasisPoints(local.height, boundary.size.height);
      final offset = metrics?.offsetPx ?? 0;
      final horizontal = metrics?.axis == ScreenScrollAxis.horizontal;
      final contentX =
          horizontal ? offset + local.left.round() : local.left.round();
      final contentY =
          horizontal ? local.top.round() : offset + local.top.round();
      final label = node.label;
      final labelJson = label == null ? '' : ',"label":${jsonEncode(label)}';
      items.add(
        '{"path":${jsonEncode(node.path)},"role":${jsonEncode(node.role)}'
        '$labelJson,'
        '"xBp":$xBp,"yBp":$yBp,"wBp":$wBp,"hBp":$hBp,'
        '"contentX":$contentX,"contentY":$contentY,'
        '"contentW":${local.width.round()},"contentH":${local.height.round()}}',
      );
    }
    final port = _scrollport;
    if (port != null && port.width >= 40 && port.height >= 40) {
      final xBp = toBasisPoints(port.left, boundary.size.width);
      final yBp = toBasisPoints(port.top, boundary.size.height);
      final wBp = toBasisPoints(port.width, boundary.size.width);
      final hBp = toBasisPoints(port.height, boundary.size.height);
      items.add(
        '{"path":"$screenHeatmapScrollportPath","role":"scrollport",'
        '"xBp":$xBp,"yBp":$yBp,"wBp":$wBp,"hBp":$hBp,'
        '"contentX":${port.left.round()},"contentY":${port.top.round()},'
        '"contentW":${port.width.round()},"contentH":${port.height.round()}}',
      );
    }
    final vw = metrics?.viewportWidth ?? boundary.size.width.round();
    final vh = metrics?.viewportHeight ?? boundary.size.height.round();
    final cw = metrics?.contentWidth ?? vw;
    final ch = metrics?.contentHeight ?? vh;
    return '{"v":1,"viewportWidth":$vw,"viewportHeight":$vh,'
        '"contentWidth":$cw,"contentHeight":$ch,'
        '"nodes":[${items.join(',')}]}';
  }

  Rect? _scrollportOf(RenderBox boundary, ScrollableState scrollable) {
    final box = scrollable.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    final origin = boundary.globalToLocal(box.localToGlobal(Offset.zero));
    final rect = (origin & box.size).intersect(Offset.zero & boundary.size);
    if (rect.width < 40 || rect.height < 40) return null;
    return rect;
  }

  Future<void> _nextFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) completer.complete();
    });
    WidgetsBinding.instance.scheduleFrame();
    return completer.future;
  }

  Future<List<int>?> _captureFoldPng({Rect? crop}) async {
    if (_background || _capturing) return null;
    final boundary = _boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) return null;
    var ratio = _targetRatio(boundary.size);
    _capturing = true;
    try {
      List<int>? best;
      for (var attempt = 0; attempt < 3; attempt++) {
        final bytes = await _renderPng(boundary, ratio, crop: crop);
        if (bytes == null) return best;
        if (bytes.length <= _maxPngBytes) return bytes;
        best = bytes;
        ratio *= 0.65;
        if (ratio < 0.3) break;
      }
      if (best != null && best.length <= 512 * 1024) return best;
      return null;
    } finally {
      _capturing = false;
    }
  }

  double _targetRatio(Size size) {
    final edge = math.max(size.width, size.height);
    if (edge <= 0) return 1;
    // Prefer modest density — rare idle / rest shot, not a filmstrip loop.
    return math.min(1.5, 1200 / edge);
  }

  Future<List<int>?> _renderPng(
    RenderRepaintBoundary boundary,
    double ratio, {
    Rect? crop,
  }) async {
    try {
      final image = await boundary.toImage(pixelRatio: ratio);
      final root = _boundaryKey.currentContext as Element?;
      final masks = root != null
          ? heatmapCoverRects(
              root: root,
              boundary: boundary,
              ratio: ratio,
              privacy: widget.privacy,
            )
          : (covers: const <Rect>[], holes: const <Rect>[]);
      var painted = masks.covers.isEmpty
          ? image
          : await _cover(image, masks.covers, masks.holes);
      if (crop != null) {
        final cropped = await _crop(painted, crop, ratio);
        if (identical(cropped, painted)) {
          if (!identical(painted, image)) painted.dispose();
          image.dispose();
          return null;
        }
        if (!identical(painted, image)) painted.dispose();
        painted = cropped;
      }
      final data = await painted.toByteData(format: ui.ImageByteFormat.png);
      painted.dispose();
      if (!identical(painted, image)) image.dispose();
      if (data == null) return null;
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<ui.Image> _cover(
      ui.Image image, List<Rect> rects, List<Rect> holes) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(image, Offset.zero, Paint());
    final paint = Paint()..color = const Color(0xFF1C1C1C);
    for (final rect in rects) {
      canvas.drawRect(rect, paint);
    }
    for (final hole in holes) {
      canvas.drawImageRect(image, hole, hole, Paint());
    }
    final picture = recorder.endRecording();
    final out = await picture.toImage(image.width, image.height);
    picture.dispose();
    return out;
  }

  Future<ui.Image> _crop(ui.Image image, Rect logical, double ratio) async {
    final bounds = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final src = Rect.fromLTWH(
      logical.left * ratio,
      logical.top * ratio,
      logical.width * ratio,
      logical.height * ratio,
    ).intersect(bounds);
    if (src.width < 1 || src.height < 1) return image;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      image,
      src,
      Rect.fromLTWH(0, 0, src.width, src.height),
      Paint(),
    );
    final picture = recorder.endRecording();
    final out = await picture.toImage(src.width.round(), src.height.round());
    picture.dispose();
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    _orientationName = size.width > size.height ? 'landscape' : 'portrait';
    _keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 100;
    final shortSide = size.shortestSide;
    _deviceClassName = shortSide >= 1024
        ? 'desktop'
        : shortSide >= 600
            ? 'tablet'
            : 'mobile';
    final client = Talaria.getClient();
    if (client != null) {
      ScreenHeatmapController.instance.client = client;
      if (!_flushHooked) {
        client.addBeforeFlush(_onClientFlush);
        _flushHooked = true;
      }
      if (!_session.isOpen && !_openScheduled) {
        _openScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _openScheduled = false;
          if (mounted) unawaited(_syncRoute());
        });
      }
    }
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        // Boundary exists only so the rare idle fold PNG can call toImage.
        child: RepaintBoundary(
          key: _boundaryKey,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Manual screen name for shells that do not change the route.
void talariaSetHeatmapScreen(String name) {
  ScreenHeatmapController.instance.setManualScreen(name);
}

/// True when the app is not on screen.
///
/// [AppLifecycleState.inactive] is an unfocused window, which is still
/// visible on desktop and web. Capture continues so a dashboard in another
/// window still records.
bool screenHeatmapAppIsHidden(AppLifecycleState state) {
  return switch (state) {
    AppLifecycleState.paused ||
    AppLifecycleState.hidden ||
    AppLifecycleState.detached =>
      true,
    AppLifecycleState.resumed || AppLifecycleState.inactive => false,
  };
}
