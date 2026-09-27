import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:talaria/talaria.dart';

import 'classifier.dart';
import 'element_path.dart';
import 'scroll_tracker.dart';
import 'session.dart';

/// Names a control the way `data-talaria-heatmap` names a DOM node.
class TalariaHeatmapAnchor extends StatelessWidget {
  const TalariaHeatmapAnchor(
      {super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(identifier: id, container: true, child: child);
  }
}

/// Always covered in snapshots. Taps are attributed to this container.
class TalariaMask extends StatelessWidget {
  const TalariaMask({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Opts a subtree out of the default text and image covers.
class TalariaUnmask extends StatelessWidget {
  const TalariaUnmask({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Captures taps, scroll depth, and masked screenshots for the screen heatmap.
class TalariaScreenCapture extends StatefulWidget {
  const TalariaScreenCapture({super.key, required this.child});

  final Widget child;

  @override
  State<TalariaScreenCapture> createState() => _TalariaScreenCaptureState();
}

class _TalariaScreenCaptureState extends State<TalariaScreenCapture>
    with WidgetsBindingObserver {
  final _boundaryKey = GlobalKey();
  final _session = ScreenHeatmapSession();
  Timer? _flush;
  Timer? _frames;
  var _flushing = false;
  var _capturing = false;
  final _snapshotSent = <String>{};
  final _recordingSent = <String>{};
  Offset? _down;
  String? _routePath;
  String? _observedRoute;
  var _manualScreen = false;
  var _background = false;
  var _flushHooked = false;
  int? _fingerprintHash;
  var _fingerprintScheduled = false;
  String _deviceClassName = 'mobile';
  String _orientationName = 'portrait';
  var _keyboardOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ScreenHeatmapController.instance.session = _session;
    ScreenHeatmapController.instance.listenScreen(_onManualScreen);
    ScreenHeatmapController.instance.listenRoute(_onObservedRoute);
    FocusManager.instance.addListener(_onFocus);
    _flush = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_flushSession(uploadVisuals: false));
    });
    _frames = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_captureFrame());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = Router.maybeOf(context)?.routeInformationProvider;
    provider?.removeListener(_onRoute);
    provider?.addListener(_onRoute);
    _onRoute();
  }

  @override
  void dispose() {
    Router.maybeOf(context)?.routeInformationProvider?.removeListener(_onRoute);
    WidgetsBinding.instance.removeObserver(this);
    _flush?.cancel();
    _frames?.cancel();
    ScreenHeatmapController.instance.unlistenScreen(_onManualScreen);
    ScreenHeatmapController.instance.unlistenRoute(_onObservedRoute);
    FocusManager.instance.removeListener(_onFocus);
    ScreenHeatmapController.instance.client?.removeBeforeFlush(_onClientFlush);
    if (ScreenHeatmapController.instance.session == _session) {
      ScreenHeatmapController.instance.session = null;
    }
    unawaited(_flushSession(uploadVisuals: true));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _background = state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused;
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
  }

  Future<void> _onClientFlush() => _flushSession(uploadVisuals: true);

  void _onRoute() {
    final uri = Router.maybeOf(context)?.routeInformationProvider?.value.uri;
    final path = uri?.path;
    if (path == null || path.isEmpty || path == _routePath) return;
    _routePath = path;
    _manualScreen = false;
    ScreenHeatmapController.instance.manualScreen = null;
    unawaited(_open(path));
  }

  Future<void> _open(String key) async {
    if (!ScreenHeatmapController.instance.captureEnabled || _background) return;
    if (_session.isOpen && _session.screenKey == key) return;
    if (_session.isOpen) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _session.classifier.noteEffect(now);
      _session.classifier.flushAll(now);
      await _flushSession(uploadVisuals: true);
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
  }

  void _onPointerDown(PointerDownEvent event) {
    _down = event.position;
  }

  void _onPointerUp(PointerUpEvent event) {
    final start = _down;
    _down = null;
    if (start == null) return;
    if ((event.position - start).distance > 18) return;
    if (!ScreenHeatmapController.instance.captureEnabled || _background) return;
    final key = _screenKey;
    if (key == null || key.isEmpty) return;
    if (!_session.isOpen) unawaited(_open(key));
    final hit = _hit(event.position);
    if (hit == null) return;
    final boundary = _boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderBox || !boundary.hasSize) return;
    final local = boundary.globalToLocal(event.position);
    final metrics = _session.scroll.state;
    final horizontal = metrics?.axis == ScreenScrollAxis.horizontal;
    final contentX =
        (horizontal ? (metrics?.offsetPx ?? 0) + local.dx : local.dx).round();
    final contentY =
        (horizontal ? local.dy : (metrics?.offsetPx ?? 0) + local.dy).round();
    final inside = event.position - hit.rect.topLeft;
    _session.classifier.add(
      TapSample(
        path: buildElementPath(hit.node),
        role: hit.node.role,
        relX: toBasisPoints(inside.dx, hit.rect.width),
        relY: toBasisPoints(inside.dy, hit.rect.height),
        xBp: toBasisPoints(local.dx, boundary.size.width),
        yBp: toBasisPoints(local.dy, boundary.size.height),
        contentX: contentX < 0 ? 0 : contentX,
        contentY: contentY < 0 ? 0 : contentY,
        clientX: local.dx,
        clientY: local.dy,
        deadEligible: tapDeadEligible(hit.node) && !_textSelectionActive(),
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
    if (_manualScreen && manual != null && manual.isNotEmpty) return manual;
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
    }
    _session.scroll.update(
      viewportWidth: size.width.round(),
      viewportHeight: size.height.round(),
      pixels: notification.metrics.pixels,
      maxScrollExtent: notification.metrics.maxScrollExtent,
      viewportDimension: notification.metrics.viewportDimension,
      vertical: vertical,
    );
    final bucket = notification.metrics.viewportDimension <= 0
        ? 0
        : (notification.metrics.pixels / notification.metrics.viewportDimension)
            .floor();
    if (bucket > 0) {
      unawaited(_captureTile(
          bucket * notification.metrics.viewportDimension.round()));
    }
    return false;
  }

  ({HeatmapElementNode node, Rect rect})? _hit(Offset global) {
    final root = _boundaryKey.currentContext as Element?;
    if (root == null) return null;
    ({HeatmapElementNode node, Rect rect})? found;
    void visit(Element element, HeatmapElementNode? parent,
        {required bool unmasked}) {
      final widget = element.widget;
      final nextUnmasked = unmasked || widget is TalariaUnmask;
      HeatmapElementNode? node = parent;
      if (widget is TalariaHeatmapAnchor ||
          widget is Semantics ||
          widget is TalariaMask) {
        final box = element.renderObject;
        if (box is RenderBox && box.hasSize && box.attached) {
          final topLeft = box.localToGlobal(Offset.zero);
          final rect = topLeft & box.size;
          if (rect.contains(global)) {
            final anchor = widget is TalariaHeatmapAnchor
                ? widget.id
                : widget is Semantics
                    ? widget.properties.identifier
                    : null;
            final props = widget is Semantics ? widget.properties : null;
            final role = widget is TalariaMask ? 'node' : _role(props);
            node = HeatmapElementNode(
              anchor: anchor,
              role: role,
              siblingIndex: _siblingIndex(element, role),
              parent: parent,
              masked: widget is TalariaMask,
              deadEligible: props?.textField != true && props?.slider != true,
            );
            found = (node: node, rect: rect);
          }
        }
      }
      if (widget is EditableText) {
        final box = element.renderObject;
        if (box is RenderBox && box.hasSize && box.attached) {
          final topLeft = box.localToGlobal(Offset.zero);
          final rect = topLeft & box.size;
          if (rect.contains(global)) {
            found = (
              node: HeatmapElementNode(
                role: 'textField',
                siblingIndex: _siblingIndex(element, 'textField'),
                parent: parent,
                deadEligible: false,
              ),
              rect: rect,
            );
          }
        }
      }
      element
          .visitChildren((child) => visit(child, node, unmasked: nextUnmasked));
    }

    visit(root, null, unmasked: false);
    return found;
  }

  String _role(SemanticsProperties? props) {
    if (props == null) return 'node';
    if (props.button == true) return 'button';
    if (props.link == true) return 'link';
    if (props.textField == true) return 'textField';
    if (props.slider == true) return 'slider';
    if (props.image == true) return 'image';
    if (props.checked != null || props.toggled != null) return 'checkbox';
    return 'node';
  }

  Future<void> _flushSession({required bool uploadVisuals}) async {
    if (_flushing) return;
    final client =
        ScreenHeatmapController.instance.client ?? Talaria.getClient();
    if (client == null || !_session.isOpen) return;
    _flushing = true;
    try {
      await _flushOpenSession(client, uploadVisuals: uploadVisuals);
    } catch (_) {
    } finally {
      _flushing = false;
    }
  }

  Future<void> _flushOpenSession(
    TalariaClient client, {
    required bool uploadVisuals,
  }) async {
    _session.classifier.tick(DateTime.now().millisecondsSinceEpoch);
    final view = _session.toView(
      anonymousId: client.anonymousId,
      sessionId: client.sessionId,
      userId: client.userId,
      release: client.options.release,
      environment: client.options.environment.wireValue,
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
      final requests = response['snapshotRequests'];
      final id = _session.screenViewId;
      final requested = id != null && requests is List && requests.contains(id);
      if (requested && !_snapshotSent.contains(id)) {
        final shot = await _capturePng(mask: true);
        if (shot != null && _session.screenViewId == id) {
          final input = _session.snapshotInput(
            png: shot,
            manifestJson: _manifestJson(),
            nowMs: DateTime.now().millisecondsSinceEpoch,
          );
          if (input != null) {
            await client.uploadScreenHeatmapSnapshot(input);
            _snapshotSent.add(id);
          }
        }
      }
      if (uploadVisuals || _session.wantsRecording) {
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

  int _siblingIndex(Element self, String role) {
    var index = 0;
    var found = false;
    self.visitAncestorElements((ancestor) {
      ancestor.visitChildren((child) {
        if (found) return;
        if (identical(child, self)) {
          found = true;
          return;
        }
        if (_elementRole(child) == role) index++;
      });
      return false;
    });
    return index;
  }

  String _elementRole(Element element) {
    final widget = element.widget;
    if (widget is Semantics) return _role(widget.properties);
    if (widget is EditableText) return 'textField';
    return 'node';
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
          widget is TalariaMask) {
        final box = element.renderObject;
        if (box is RenderBox && box.hasSize && box.attached) {
          final rect = box.localToGlobal(Offset.zero) & box.size;
          hash = Object.hash(
            hash,
            _elementRole(element),
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
      return '[]';
    }
    final origin = boundary.localToGlobal(Offset.zero);
    final metrics = _session.scroll.state;
    final items = <String>[];
    void visit(Element element, HeatmapElementNode? parent) {
      if (items.length >= 200) return;
      final widget = element.widget;
      HeatmapElementNode? node = parent;
      if (widget is TalariaHeatmapAnchor ||
          widget is Semantics ||
          widget is TalariaMask) {
        final box = element.renderObject;
        if (box is RenderBox && box.hasSize && box.attached) {
          final role = widget is TalariaMask ? 'node' : _elementRole(element);
          final anchor = widget is TalariaHeatmapAnchor
              ? widget.id
              : widget is Semantics
                  ? widget.properties.identifier
                  : null;
          node = HeatmapElementNode(
            anchor: anchor,
            role: role,
            siblingIndex: _siblingIndex(element, role),
            parent: parent,
            masked: widget is TalariaMask,
          );
          final local = box.localToGlobal(Offset.zero) - origin;
          final path = buildElementPath(node);
          final xBp = toBasisPoints(local.dx, boundary.size.width);
          final yBp = toBasisPoints(local.dy, boundary.size.height);
          final wBp = toBasisPoints(box.size.width, boundary.size.width);
          final hBp = toBasisPoints(box.size.height, boundary.size.height);
          final offset = metrics?.offsetPx ?? 0;
          final horizontal = metrics?.axis == ScreenScrollAxis.horizontal;
          final contentX =
              horizontal ? offset + local.dx.round() : local.dx.round();
          final contentY =
              horizontal ? local.dy.round() : offset + local.dy.round();
          items.add(
            '{"path":${jsonEncode(path)},"role":${jsonEncode(role)},'
            '"xBp":$xBp,"yBp":$yBp,"wBp":$wBp,"hBp":$hBp,'
            '"contentX":$contentX,"contentY":$contentY,'
            '"contentW":${box.size.width.round()},"contentH":${box.size.height.round()}}',
          );
        }
      }
      element.visitChildren((child) => visit(child, node));
    }

    visit(root, null);
    return '[${items.join(',')}]';
  }

  Future<void> _captureFrame() async {
    if (_background || !ScreenHeatmapController.instance.captureEnabled) return;
    if (!_session.recordFilmstrip && !_session.wantsRecording) return;
    final png = await _capturePng(mask: true);
    if (png == null) return;
    _session.addFrame(
      png,
      DateTime.now().millisecondsSinceEpoch - _session.startedAtMs,
    );
  }

  Future<void> _captureTile(int offsetPx) async {
    if (_session.tiles.containsKey(offsetPx)) return;
    final png = await _capturePng(mask: true);
    if (png != null) _session.addTile(offsetPx, png);
  }

  Future<List<int>?> _capturePng({required bool mask}) async {
    if (_background || _capturing) return null;
    final boundary = _boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) return null;
    final longEdge = math.max(boundary.size.width, boundary.size.height);
    final ratio = longEdge <= 0 ? 0.5 : math.min(0.5, 800 / longEdge);
    _capturing = true;
    try {
      final image = await boundary.toImage(pixelRatio: ratio);
      final masks = mask
          ? _maskRegions(boundary, ratio)
          : (covers: const <Rect>[], holes: const <Rect>[]);
      final painted = masks.covers.isEmpty
          ? image
          : await _cover(image, masks.covers, masks.holes);
      final data = await painted.toByteData(format: ui.ImageByteFormat.png);
      painted.dispose();
      if (!identical(painted, image)) image.dispose();
      if (data == null) return null;
      final bytes = data.buffer.asUint8List();
      if (bytes.length > 512 * 1024) return null;
      return bytes;
    } catch (_) {
      return null;
    } finally {
      _capturing = false;
    }
  }

  ({List<Rect> covers, List<Rect> holes}) _maskRegions(
      RenderBox boundary, double ratio) {
    final root = _boundaryKey.currentContext as Element?;
    if (root == null) return (covers: const <Rect>[], holes: const <Rect>[]);
    final origin = boundary.localToGlobal(Offset.zero);
    final covers = <Rect>[];
    final holes = <Rect>[];
    void visit(Element element, {required bool unmasked, required bool force}) {
      final widget = element.widget;
      final optedOut = unmasked || widget is TalariaUnmask;
      final inMask = (force || widget is TalariaMask) && !optedOut;
      final coverDefault = !optedOut &&
          (widget is Text ||
              widget is EditableText ||
              widget is RichText ||
              widget is Image);
      final box = element.renderObject;
      if (box is RenderBox && box.hasSize && box.attached) {
        final rect =
            _scale(box.localToGlobal(Offset.zero) - origin & box.size, ratio);
        if (widget is TalariaUnmask && force) holes.add(rect);
        if (inMask || coverDefault) covers.add(rect);
      }
      element.visitChildren(
        (child) => visit(child, unmasked: optedOut, force: inMask),
      );
    }

    visit(root, unmasked: false, force: false);
    return (covers: covers, holes: holes);
  }

  Rect _scale(Rect rect, double ratio) => Rect.fromLTRB(
        rect.left * ratio,
        rect.top * ratio,
        rect.right * ratio,
        rect.bottom * ratio,
      );

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
    }
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
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
