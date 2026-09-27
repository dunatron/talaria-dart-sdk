enum ScreenScrollAxis { vertical, horizontal, none }

class ScreenScrollState {
  const ScreenScrollState({
    required this.viewportWidth,
    required this.viewportHeight,
    required this.contentWidth,
    required this.contentHeight,
    required this.maxDepthPx,
    required this.initialFoldPx,
    required this.axis,
    required this.offsetPx,
  });

  final int viewportWidth;
  final int viewportHeight;
  final int contentWidth;
  final int contentHeight;
  final int maxDepthPx;
  final int initialFoldPx;
  final ScreenScrollAxis axis;
  final int offsetPx;
}

/// Primary scrollable for one screen view. The largest scroller is the document.
class ScreenScrollTracker {
  ScreenScrollState? _state;

  ScreenScrollState? get state => _state;

  void update({
    required int viewportWidth,
    required int viewportHeight,
    required double pixels,
    required double maxScrollExtent,
    required double viewportDimension,
    required bool vertical,
  }) {
    final viewport = viewportDimension.round().clamp(0, 1 << 20);
    final content = (maxScrollExtent + viewportDimension).round().clamp(viewport, 1 << 20);
    final depth = (pixels + viewportDimension).round().clamp(0, content);
    final axis = vertical ? ScreenScrollAxis.vertical : ScreenScrollAxis.horizontal;
    final current = _state;
    if (current == null) {
      _state = ScreenScrollState(
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
        contentWidth: vertical ? viewportWidth : content,
        contentHeight: vertical ? content : viewportHeight,
        maxDepthPx: depth,
        initialFoldPx: vertical ? viewportHeight : viewportWidth,
        axis: axis,
        offsetPx: pixels.round().clamp(0, content),
      );
      return;
    }
    _state = ScreenScrollState(
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      contentWidth: vertical
          ? viewportWidth
          : (content > current.contentWidth ? content : current.contentWidth),
      contentHeight: vertical
          ? (content > current.contentHeight ? content : current.contentHeight)
          : viewportHeight,
      maxDepthPx: depth > current.maxDepthPx ? depth : current.maxDepthPx,
      initialFoldPx: current.initialFoldPx,
      axis: current.axis == ScreenScrollAxis.none ? axis : current.axis,
      offsetPx: pixels.round().clamp(0, content),
    );
  }

  void ensureFold({required int viewportWidth, required int viewportHeight}) {
    _state ??= ScreenScrollState(
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      contentWidth: viewportWidth,
      contentHeight: viewportHeight,
      maxDepthPx: viewportHeight,
      initialFoldPx: viewportHeight,
      axis: ScreenScrollAxis.none,
      offsetPx: 0,
    );
  }
}

/// Prefer the vertical scroller that covers the most of the screen.
bool isPrimaryScroll({
  required double viewportArea,
  required double bestArea,
  required bool vertical,
  required bool bestVertical,
}) {
  if (bestArea <= 0) return true;
  if (vertical && !bestVertical) return true;
  if (!vertical && bestVertical) return false;
  return viewportArea > bestArea;
}
