import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:talaria_flutter/src/heatmaps/capture.dart';
import 'package:talaria_flutter/src/heatmaps/classifier.dart';
import 'package:talaria_flutter/src/heatmaps/element_path.dart';
import 'package:talaria_flutter/src/heatmaps/scroll_tracker.dart';
import 'package:talaria_flutter/src/heatmaps/session.dart';

TapSample _tap({
  String path = 'button:0',
  double x = 10,
  double y = 10,
  bool deadEligible = true,
  String role = 'button',
}) {
  return TapSample(
    path: path,
    role: role,
    relX: 0,
    relY: 0,
    xBp: 0,
    yBp: 0,
    contentX: x.round(),
    contentY: y.round(),
    clientX: x,
    clientY: y,
    deadEligible: deadEligible,
  );
}

void main() {
  test('an unfocused window still captures heatmaps', () {
    expect(screenHeatmapAppIsHidden(AppLifecycleState.inactive), isFalse);
    expect(screenHeatmapAppIsHidden(AppLifecycleState.resumed), isFalse);
    expect(screenHeatmapAppIsHidden(AppLifecycleState.paused), isTrue);
    expect(screenHeatmapAppIsHidden(AppLifecycleState.hidden), isTrue);
    expect(screenHeatmapAppIsHidden(AppLifecycleState.detached), isTrue);
  });

  test('rage burst marks three taps inside the window and radius', () {
    final out = <ClassifiedTap>[];
    final classifier = ScreenTapClassifier(out.add);
    classifier.add(_tap(), 0);
    classifier.add(_tap(x: 12), 400);
    classifier.add(_tap(x: 20), 800);
    classifier.flushAll(3000);
    expect(out, hasLength(3));
    expect(out.every((tap) => tap.rage), isTrue);
  });

  test('a tap with no effect is dead after the observe window', () {
    final out = <ClassifiedTap>[];
    final classifier = ScreenTapClassifier(out.add);
    classifier.add(_tap(), 0);
    classifier.tick(2000);
    expect(out.single.dead, isTrue);
    expect(out.single.rage, isFalse);
  });

  test('an effect before the window closes is not dead', () {
    final out = <ClassifiedTap>[];
    final classifier = ScreenTapClassifier(out.add);
    classifier.add(_tap(), 0);
    classifier.noteEffect(500);
    classifier.flushAll(2000);
    expect(out.single.dead, isFalse);
  });

  test('a text field tap is not dead', () {
    final out = <ClassifiedTap>[];
    final classifier = ScreenTapClassifier(out.add);
    classifier.add(_tap(role: 'textField', deadEligible: false), 0);
    classifier.flushAll(2000);
    expect(out.single.dead, isFalse);
  });

  test('an error inside two seconds flags the tap', () {
    final out = <ClassifiedTap>[];
    final classifier = ScreenTapClassifier(out.add);
    classifier.add(_tap(), 0);
    classifier.noteError(1500);
    classifier.flushAll(2000);
    expect(out.single.error, isTrue);
  });

  test('a press on a different path ends observation', () {
    final out = <ClassifiedTap>[];
    final classifier = ScreenTapClassifier(out.add);
    classifier.add(_tap(path: 'button:0'), 0);
    classifier.add(_tap(path: 'button:1'), 100);
    classifier.flushAll(100);
    expect(out.first.dead, isTrue);
    expect(out.last.dead, isFalse);
  });

  test('anchor wins and a mask container steals the path', () {
    final button = HeatmapElementNode(
      role: 'button',
      siblingIndex: 2,
      parent: const HeatmapElementNode(role: 'scrollable', siblingIndex: 0),
    );
    expect(buildElementPath(button), 'button:2');

    final anchored = HeatmapElementNode(
      role: 'button',
      siblingIndex: 4,
      anchor: 'checkout_pay',
      parent: const HeatmapElementNode(role: 'scrollable', siblingIndex: 0),
    );
    expect(buildElementPath(anchored), 'checkout_pay');

    final masked = HeatmapElementNode(
      role: 'button',
      siblingIndex: 1,
      parent: const HeatmapElementNode(
        role: 'node',
        siblingIndex: 0,
        anchor: 'secret_card',
        masked: true,
      ),
    );
    expect(buildElementPath(masked), 'secret_card');
    expect(buildElementPath(masked).contains('label'), isFalse);
  });

  test('labels name a control and unlabeled wrappers are omitted', () {
    final save = HeatmapElementNode(
      role: 'button',
      siblingIndex: 0,
      label: 'Save',
      parent: const HeatmapElementNode(role: 'node', siblingIndex: 0),
    );
    expect(buildElementPath(save), 'button:Save');

    final second = HeatmapElementNode(
      role: 'button',
      siblingIndex: 1,
      label: 'Save',
    );
    expect(buildElementPath(second), 'button:Save#1');
    expect(safeHeatmapLabel('user@example.com'), isNull);
    expect(safeHeatmapLabel('12'), isNull);
    expect(safeHeatmapLabel('Pay now'), 'Pay now');
  });

  test('unsafe anchors and deep paths are capped', () {
    expect(isSafeAnchor('user@example.com'), isFalse);
    expect(isSafeAnchor('order-1234'), isFalse);
    HeatmapElementNode? node =
        const HeatmapElementNode(role: 'row', siblingIndex: 0);
    for (var i = 0; i < 20; i++) {
      node = HeatmapElementNode(role: 'row', siblingIndex: i, parent: node);
    }
    expect(buildElementPath(node!), 'row:19');
    expect(buildElementPath(node).length, lessThanOrEqualTo(512));
  });

  test('text fields are not dead-eligible', () {
    final field = HeatmapElementNode(
      role: 'textField',
      siblingIndex: 0,
      deadEligible: false,
    );
    expect(tapDeadEligible(field), isFalse);
  });

  test('the largest vertical scroller is the document', () {
    expect(
      isPrimaryScroll(
        viewportArea: 400,
        bestArea: 10000,
        vertical: false,
        bestVertical: true,
      ),
      isFalse,
    );
    expect(
      isPrimaryScroll(
        viewportArea: 8000,
        bestArea: 1000,
        vertical: true,
        bestVertical: false,
      ),
      isTrue,
    );
  });

  test('lazy content height grows and a static screen is full reach', () {
    final tracker = ScreenScrollTracker();
    tracker.ensureFold(viewportWidth: 400, viewportHeight: 800);
    expect(tracker.state!.contentHeight, 800);
    expect(tracker.state!.maxDepthPx, 800);
    tracker.update(
      viewportWidth: 400,
      viewportHeight: 800,
      pixels: 200,
      maxScrollExtent: 400,
      viewportDimension: 800,
      vertical: true,
    );
    tracker.update(
      viewportWidth: 400,
      viewportHeight: 800,
      pixels: 900,
      maxScrollExtent: 1200,
      viewportDimension: 800,
      vertical: true,
    );
    expect(tracker.state!.contentHeight, 2000);
    expect(tracker.state!.maxDepthPx, 1700);
    expect(tracker.state!.initialFoldPx, 800);
  });

  test('only a scroller that covers most of the window is the page', () {
    expect(
      screenHeatmapScrollIsPage(
        width: 869,
        height: 877,
        boundaryWidth: 1109,
        boundaryHeight: 929,
        maxScrollExtent: 1200,
      ),
      isTrue,
    );
    expect(
      screenHeatmapScrollIsPage(
        width: 360,
        height: 420,
        boundaryWidth: 1109,
        boundaryHeight: 929,
        maxScrollExtent: 800,
      ),
      isFalse,
    );
    expect(
      screenHeatmapScrollIsPage(
        width: 900,
        height: 800,
        boundaryWidth: 1109,
        boundaryHeight: 929,
        maxScrollExtent: 0,
      ),
      isFalse,
    );
  });

  test(
      'a scrolled page is captured one viewport at a time, including the bottom',
      () {
    expect(
      screenHeatmapTileOffsets(viewport: 800, maxScrollExtent: 2000),
      [800, 1600, 2000],
    );
    expect(
      screenHeatmapTileOffsets(viewport: 800, maxScrollExtent: 1600),
      [800, 1600],
    );
    expect(
      screenHeatmapTileOffsets(viewport: 800, maxScrollExtent: 0),
      isEmpty,
    );
    final tracker = ScreenScrollTracker();
    tracker.ensureFold(viewportWidth: 400, viewportHeight: 800);
    tracker.update(
      viewportWidth: 400,
      viewportHeight: 800,
      pixels: 40,
      maxScrollExtent: 0,
      viewportDimension: 800,
      vertical: true,
    );
    tracker.noteContentExtent(
      contentWidth: 400,
      contentHeight: 2400,
      vertical: true,
    );
    expect(tracker.state!.contentHeight, 2400);
    expect(tracker.state!.maxDepthPx, 800);
    expect(tracker.state!.offsetPx, 40);
  });

  test('snapshot input allows structural-only when png is empty', () {
    final session = ScreenHeatmapSession(random: _FixedRandom());
    session.open(
      screenKey: '/checkout',
      nowMs: 0,
      viewportWidth: 400,
      viewportHeight: 800,
    );
    final input = session.snapshotInput(
      png: const [],
      manifestJson: '{"v":1,"nodes":[]}',
      nowMs: 1000,
    );
    expect(input, isNotNull);
    expect(input!['pngBytes'], isEmpty);
    expect(input['manifestJson'], '{"v":1,"nodes":[]}');
    expect(input['tiles'], isEmpty);
  });

  test('opportunistic tiles and micro-frames stay capped', () {
    final session = ScreenHeatmapSession(random: _FixedRandom());
    session.open(
      screenKey: '/checkout',
      nowMs: 0,
      viewportWidth: 400,
      viewportHeight: 800,
    );
    for (var i = 1; i <= 10; i++) {
      session.addTile(i * 800, List<int>.filled(10, i));
    }
    expect(session.tiles.length, 8);
    session.addTile(0, const [1]); // fold offset ignored
    expect(session.tiles.containsKey(0), isFalse);

    session.classifier.add(_tap(), 0);
    session.classifier.flushAll(2000);
    expect(session.recordingId, isNotNull); // dead tap
    session.addFrame(List<int>.filled(600 * 1024, 1), 0);
    expect(session.frames, isEmpty);
    session.addFrame(const [1, 2, 3], 10);
    session.addFrame(const [4, 5, 6], 20);
    session.addFrame(const [7, 8, 9], 30);
    session.addFrame(const [10], 40);
    expect(session.frames, hasLength(3));
    expect(session.wantsRecording, isTrue);
    expect(session.recordingInput()?['frames'], hasLength(3));
  });

  test('later flushes omit taps that were already sent', () {
    final session = ScreenHeatmapSession(
      random: _FixedRandom(),
    );
    session.open(
      screenKey: '/home',
      nowMs: 0,
      viewportWidth: 390,
      viewportHeight: 800,
    );
    const layout = (
      deviceClass: 'mobile',
      orientation: 'portrait',
      keyboard: false,
    );
    session.classifier.add(_tap(path: 'button:0'), 10);
    session.classifier.flushAll(10);
    expect(
        session.shouldSend(
            deviceClass: 'mobile', orientation: 'portrait', keyboard: false),
        isTrue);

    final first = _view(session);
    final firstTaps = first['taps'] as List;
    expect(firstTaps, hasLength(1));
    expect(firstTaps.single['tapIndex'], 0);
    session.markSent(
      throughTap: session.unsentTapEnd,
      deviceClass: layout.deviceClass,
      orientation: layout.orientation,
      keyboard: layout.keyboard,
    );
    expect(
      session.shouldSend(
        deviceClass: 'mobile',
        orientation: 'portrait',
        keyboard: false,
      ),
      isFalse,
    );
    expect(_view(session)['taps'], isEmpty);

    session.scroll.update(
      viewportWidth: 390,
      viewportHeight: 800,
      pixels: 0,
      maxScrollExtent: 0,
      viewportDimension: 800,
      vertical: true,
    );
    expect(
      session.shouldSend(
        deviceClass: 'mobile',
        orientation: 'portrait',
        keyboard: false,
      ),
      isFalse,
    );

    session.classifier.add(_tap(path: 'button:1'), 40);
    session.classifier.flushAll(40);
    expect(
      session.shouldSend(
        deviceClass: 'mobile',
        orientation: 'portrait',
        keyboard: false,
      ),
      isTrue,
    );
    final more = _view(session)['taps'] as List;
    expect(more, hasLength(1));
    expect(more.single['path'], 'button:1');
    expect(more.single['tapIndex'], 1);
  });

  test('the view payload has no label text', () {
    final session = ScreenHeatmapSession(random: _FixedRandom());
    session.open(
        screenKey: '/home', nowMs: 0, viewportWidth: 390, viewportHeight: 800);
    session.classifier.add(_tap(path: 'button:0'), 10);
    session.classifier.flushAll(10);
    final view = session.toView(
      anonymousId: 'anon',
      sessionId: 'sess',
      userId: null,
      release: '1',
      osName: 'ios',
      deviceClass: 'mobile',
      orientation: 'portrait',
      keyboard: false,
      replayId: null,
      nowMs: 20,
    );
    final encoded = view.toString();
    expect(encoded.contains('label'), isFalse);
    expect(encoded.contains('button:0'), isTrue);
  });

  test('capture stays off until heatmaps and analytics are both on', () {
    final controller = ScreenHeatmapController.instance;
    controller.client = null;
    expect(controller.captureEnabled, isFalse);
  });
}

Map<String, Object?> _view(ScreenHeatmapSession session) {
  return session.toView(
    anonymousId: 'anon',
    sessionId: 'sess',
    userId: null,
    release: '1',
    osName: 'ios',
    deviceClass: 'mobile',
    orientation: 'portrait',
    keyboard: false,
    replayId: null,
    nowMs: 50,
  )!;
}

class _FixedRandom implements Random {
  @override
  bool nextBool() => true;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => 1;
}
