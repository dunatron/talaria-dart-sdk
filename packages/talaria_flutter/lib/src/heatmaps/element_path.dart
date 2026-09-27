/// One semantics node used to build a heatmap path. No label text.
class HeatmapElementNode {
  const HeatmapElementNode({
    required this.role,
    required this.siblingIndex,
    this.anchor,
    this.parent,
    this.masked = false,
    this.deadEligible = true,
  });

  final String? anchor;
  final String role;
  final int siblingIndex;
  final HeatmapElementNode? parent;
  final bool masked;
  final bool deadEligible;
}

const maxPathDepth = 12;
const maxPathLength = 512;
const maxAnchorLength = 128;

final _email = RegExp(r'[^\s@]+@[^\s@]+');
final _longDigits = RegExp(r'\d{4,}');

bool isSafeAnchor(String value) {
  final id = value.trim();
  if (id.isEmpty || id.length > maxAnchorLength) return false;
  if (_email.hasMatch(id) || _longDigits.hasMatch(id)) return false;
  return true;
}

/// Walk to the nearest mask, otherwise build `anchor` or `role:index` segments.
String buildElementPath(HeatmapElementNode node) {
  HeatmapElementNode? current = node;
  while (current != null) {
    if (current.masked) {
      final anchor = current.anchor;
      if (anchor != null && isSafeAnchor(anchor)) return anchor.trim();
      return '${current.role}:${current.siblingIndex}';
    }
    current = current.parent;
  }

  final segments = <String>[];
  current = node;
  var depth = 0;
  while (current != null && depth < maxPathDepth) {
    final anchor = current.anchor;
    if (anchor != null && isSafeAnchor(anchor)) {
      segments.add(anchor.trim());
      break;
    }
    segments.add('${current.role}:${current.siblingIndex}');
    current = current.parent;
    depth++;
  }
  if (segments.isEmpty) return 'node:0';
  final path = segments.reversed.join('/');
  return path.length > maxPathLength ? path.substring(0, maxPathLength) : path;
}

bool tapDeadEligible(HeatmapElementNode node) {
  HeatmapElementNode? current = node;
  while (current != null) {
    if (!current.deadEligible) return false;
    current = current.parent;
  }
  return node.deadEligible;
}
