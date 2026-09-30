/// Manifest path for the scrolling viewport inside a screen snapshot.
const screenHeatmapScrollportPath = '__talaria_scrollport';

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
    final content =
        (maxScrollExtent + viewportDimension).round().clamp(viewport, 1 << 20);
    final depth = (pixels + viewportDimension).round().clamp(0, content);
    final axis =
        vertical ? ScreenScrollAxis.vertical : ScreenScrollAxis.horizontal;
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

  /// Record the scrollable's real length without treating a capture pass
  /// as the visitor having scrolled there.
  void noteContentExtent({
    required int contentWidth,
    required int contentHeight,
    required bool vertical,
  }) {
    final current = _state;
    if (current == null) return;
    _state = ScreenScrollState(
      viewportWidth: current.viewportWidth,
      viewportHeight: current.viewportHeight,
      contentWidth: vertical ? current.contentWidth : contentWidth,
      contentHeight: vertical ? contentHeight : current.contentHeight,
      maxDepthPx: current.maxDepthPx,
      initialFoldPx: current.initialFoldPx,
      axis: current.axis == ScreenScrollAxis.none
          ? (vertical ? ScreenScrollAxis.vertical : ScreenScrollAxis.horizontal)
          : current.axis,
      offsetPx: current.offsetPx,
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

/// Scroll offsets to screenshot after the fold, in scrollable pixels.
///
/// Steps one viewport at a time and always includes the bottom when the
/// document is not an exact multiple of the viewport.
List<int> screenHeatmapTileOffsets({
  required double viewport,
  required double maxScrollExtent,
  int maxTiles = 8,
}) {
  if (viewport <= 1 || maxScrollExtent <= 1 || maxTiles <= 0) return const [];
  final out = <int>[];
  var offset = viewport;
  while (out.length < maxTiles && offset < maxScrollExtent + viewport - 1) {
    final px = (offset < maxScrollExtent ? offset : maxScrollExtent).round();
    if (px <= 0) break;
    if (out.isNotEmpty && out.last == px) break;
    out.add(px);
    if (offset >= maxScrollExtent) break;
    offset += viewport;
  }
  return out;
}

/// True when a scrollable is the page, not a side list or a nested pane.
///
/// The viewport has to cover most of the window. A heatmap list or a short
/// card can scroll without being the document.
bool screenHeatmapScrollIsPage({
  required double width,
  required double height,
  required double boundaryWidth,
  required double boundaryHeight,
  required double maxScrollExtent,
}) {
  if (boundaryWidth <= 0 || boundaryHeight <= 0 || maxScrollExtent <= 24) {
    return false;
  }
  if (width < 200 || height < 200) return false;
  return width >= boundaryWidth * 0.5 && height >= boundaryHeight * 0.5;
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
