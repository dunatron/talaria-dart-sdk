import 'dart:math';

import 'package:talaria/talaria.dart';

import 'classifier.dart';
import 'scroll_tracker.dart';

class ScreenHeatmapFrameBytes {
  const ScreenHeatmapFrameBytes({required this.offsetMs, required this.png});

  final int offsetMs;
  final List<int> png;
}

/// In-memory screen view that becomes an ingest batch.
class ScreenHeatmapSession {
  ScreenHeatmapSession({Random? random}) : _random = random ?? Random();

  final Random _random;

  String? screenViewId;
  String? screenKey;
  String? recordingId;
  int startedAtMs = 0;
  final List<ClassifiedTap> taps = [];
  final ScreenScrollTracker scroll = ScreenScrollTracker();
  final List<ScreenHeatmapFrameBytes> frames = [];
  final Map<int, List<int>> tiles = {};

  late final ScreenTapClassifier classifier = ScreenTapClassifier(_onFinalized);

  void Function(ClassifiedTap tap)? onInterestingTap;

  bool get isOpen => screenViewId != null;

  /// Taps already accepted by ingest. Later flushes send only the tail.
  int _sentTaps = 0;
  int? _sentDepth;
  int? _sentContentWidth;
  int? _sentContentHeight;
  int? _sentViewportWidth;
  int? _sentViewportHeight;
  String? _sentLayout;

  /// Exclusive end index of taps included in the next payload (cap 500).
  int get unsentTapEnd {
    final capped = taps.length < 500 ? taps.length : 500;
    return capped < _sentTaps ? _sentTaps : capped;
  }

  /// False when this view was already sent and nothing the wire stores changed.
  ///
  /// Scroll offset alone does not count: the row stores max depth, not position.
  bool shouldSend({
    required String deviceClass,
    required String orientation,
    required bool keyboard,
  }) {
    final metrics = scroll.state;
    if (!isOpen || metrics == null || _sentDepth == null) {
      return isOpen && metrics != null;
    }
    if (unsentTapEnd > _sentTaps) return true;
    if (metrics.maxDepthPx != _sentDepth) return true;
    if (metrics.contentWidth != _sentContentWidth) return true;
    if (metrics.contentHeight != _sentContentHeight) return true;
    if (metrics.viewportWidth != _sentViewportWidth) return true;
    if (metrics.viewportHeight != _sentViewportHeight) return true;
    return _layout(deviceClass, orientation, keyboard) != _sentLayout;
  }

  void markSent({
    required int throughTap,
    required String deviceClass,
    required String orientation,
    required bool keyboard,
  }) {
    final metrics = scroll.state;
    _sentTaps = throughTap;
    _sentLayout = _layout(deviceClass, orientation, keyboard);
    if (metrics == null) return;
    _sentDepth = metrics.maxDepthPx;
    _sentContentWidth = metrics.contentWidth;
    _sentContentHeight = metrics.contentHeight;
    _sentViewportWidth = metrics.viewportWidth;
    _sentViewportHeight = metrics.viewportHeight;
  }

  void _resetSent() {
    _sentTaps = 0;
    _sentDepth = null;
    _sentContentWidth = null;
    _sentContentHeight = null;
    _sentViewportWidth = null;
    _sentViewportHeight = null;
    _sentLayout = null;
  }

  static String _layout(String deviceClass, String orientation, bool keyboard) {
    return '$deviceClass|$orientation|$keyboard';
  }

  void _onFinalized(ClassifiedTap tap) {
    taps.add(tap);
    if (tap.rage || tap.dead || tap.error) {
      recordingId ??= _id();
      onInterestingTap?.call(tap);
    }
  }

  void open({
    required String screenKey,
    required int nowMs,
    required int viewportWidth,
    required int viewportHeight,
  }) {
    if (isOpen && this.screenKey == screenKey) return;
    screenViewId = _id();
    this.screenKey = screenKey;
    startedAtMs = nowMs;
    recordingId = null;
    taps.clear();
    frames.clear();
    tiles.clear();
    _resetSent();
    scroll.ensureFold(
        viewportWidth: viewportWidth, viewportHeight: viewportHeight);
  }

  void close() {
    screenViewId = null;
    screenKey = null;
    recordingId = null;
    taps.clear();
    frames.clear();
    tiles.clear();
    _resetSent();
  }

  /// Opportunistic tile from the viewport the user actually rested on.
  void addTile(int offsetPx, List<int> png) {
    if (!isOpen || tiles.length >= 8 || png.length > 512 * 1024) return;
    if (offsetPx <= 0) return;
    tiles.putIfAbsent(offsetPx, () => png);
  }

  /// Event-driven micro-frames around rage / dead / error (max 3).
  void addFrame(List<int> png, int offsetMs) {
    if (!isOpen || png.length > 512 * 1024) return;
    if (frames.length >= 3) return;
    frames.add(ScreenHeatmapFrameBytes(offsetMs: offsetMs, png: png));
  }

  bool get wantsRecording => frames.isNotEmpty && recordingId != null;

  Map<String, Object?>? toView({
    required String anonymousId,
    required String sessionId,
    required String? userId,
    required String? release,
    required String? osName,
    required String deviceClass,
    required String orientation,
    required bool keyboard,
    required String? replayId,
    required int nowMs,
  }) {
    final id = screenViewId;
    final key = screenKey;
    final metrics = scroll.state;
    if (id == null || key == null || key.isEmpty || metrics == null) {
      return null;
    }
    final recording = wantsRecording ? recordingId : null;
    return {
      '__className__': 'IngestScreenHeatmapViewInput',
      'screenViewId': id,
      'screenKey': key,
      'anonymousId': anonymousId,
      'sessionId': sessionId,
      'userId': userId,
      'replayId': replayId,
      'startedAt': DateTime.fromMillisecondsSinceEpoch(startedAtMs, isUtc: true)
          .toIso8601String(),
      'updatedAt': DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true)
          .toIso8601String(),
      'viewportWidth': metrics.viewportWidth,
      'viewportHeight': metrics.viewportHeight,
      'contentWidth': metrics.contentWidth,
      'contentHeight': metrics.contentHeight,
      'maxDepthPx': metrics.maxDepthPx,
      'initialFoldPx': metrics.initialFoldPx,
      'scrollAxis': metrics.axis.name,
      'deviceClass': deviceClass,
      'orientation': orientation,
      'keyboard': keyboard,
      'osName': osName,
      'release': release,
      'platform': 'flutter',
      'taps': [
        for (var i = _sentTaps; i < unsentTapEnd; i++)
          {
            '__className__': 'IngestScreenHeatmapTapInput',
            'tapIndex': i,
            'occurredAt': DateTime.fromMillisecondsSinceEpoch(
              taps[i].occurredAt,
              isUtc: true,
            ).toIso8601String(),
            'path': taps[i].sample.path,
            'role': taps[i].sample.role,
            'relX': taps[i].sample.relX,
            'relY': taps[i].sample.relY,
            'xBp': taps[i].sample.xBp,
            'yBp': taps[i].sample.yBp,
            'contentX': taps[i].sample.contentX,
            'contentY': taps[i].sample.contentY,
            'rage': taps[i].rage,
            'dead': taps[i].dead,
            'error': taps[i].error,
            'recordingId':
                (taps[i].rage || taps[i].dead || taps[i].error) ? recording : null,
          },
      ],
    };
  }

  /// Fold PNG and/or structural [manifestJson]. At least one must be present.
  Map<String, Object?>? snapshotInput({
    required List<int> png,
    required String manifestJson,
    required int nowMs,
  }) {
    final id = screenViewId;
    final metrics = scroll.state;
    if (id == null || metrics == null) return null;
    if (png.isEmpty && manifestJson.trim().isEmpty) return null;
    return {
      '__className__': 'UploadScreenHeatmapSnapshotInput',
      'screenViewId': id,
      'pngBytes': png,
      'manifestJson': manifestJson,
      'viewportWidth': metrics.viewportWidth,
      'viewportHeight': metrics.viewportHeight,
      'contentHeight': metrics.contentHeight,
      'capturedAt': DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true)
          .toIso8601String(),
      'tiles': [
        for (final entry in tiles.entries)
          {
            '__className__': 'ScreenHeatmapTileInput',
            'offsetPx': entry.key,
            'pngBytes': entry.value,
          },
      ],
    };
  }

  Map<String, Object?>? recordingInput() {
    final id = screenViewId;
    final recording = recordingId;
    if (id == null || recording == null || frames.isEmpty) return null;
    return {
      '__className__': 'UploadScreenHeatmapRecordingInput',
      'recordingId': recording,
      'screenViewId': id,
      'frames': [
        for (final frame in frames)
          {
            '__className__': 'ScreenHeatmapFrameInput',
            'offsetMs': frame.offsetMs,
            'pngBytes': frame.png,
          },
      ],
    };
  }

  String _id() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final h = bytes.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}

/// Shared with error hooks so a captured exception can flag the open tap.
class ScreenHeatmapController {
  ScreenHeatmapController._();

  static final instance = ScreenHeatmapController._();

  ScreenHeatmapSession? session;
  TalariaClient? client;
  String? manualScreen;
  final List<void Function(String name)> _screenListeners = [];

  void setManualScreen(String name) {
    manualScreen = name;
    for (final listener in List<void Function(String)>.from(_screenListeners)) {
      listener(name);
    }
  }

  void listenScreen(void Function(String name) listener) {
    _screenListeners.add(listener);
  }

  void unlistenScreen(void Function(String name) listener) {
    _screenListeners.remove(listener);
  }

  final List<void Function(String name)> _routeListeners = [];

  /// Navigator 1.0 route name. Ignored while a manual screen or Router path is set.
  void notifyObservedRoute(String name) {
    if (manualScreen != null && manualScreen!.isNotEmpty) return;
    for (final listener in List<void Function(String)>.from(_routeListeners)) {
      listener(name);
    }
  }

  void listenRoute(void Function(String name) listener) {
    _routeListeners.add(listener);
  }

  void unlistenRoute(void Function(String name) listener) {
    _routeListeners.remove(listener);
  }

  void noteError() {
    session?.classifier
        .noteError(DateTime.now().toUtc().millisecondsSinceEpoch);
  }

  bool get captureEnabled {
    final options = client?.options;
    if (options == null) return false;
    return options.heatmapsEnabled && options.enableAnalytics;
  }
}
