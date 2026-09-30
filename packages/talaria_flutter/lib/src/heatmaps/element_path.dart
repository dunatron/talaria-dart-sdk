/// One control used to build a heatmap path.
///
/// [label] is a short sanitized accessibility or widget label. Typed field
/// values are never stored here. [siblingIndex] is the occurrence of this
/// role and label while walking the tree, so two Save buttons stay distinct.
class HeatmapElementNode {
  const HeatmapElementNode({
    required this.role,
    required this.siblingIndex,
    this.anchor,
    this.label,
    this.parent,
    this.masked = false,
    this.deadEligible = true,
  });

  final String? anchor;
  final String? label;
  final String role;
  final int siblingIndex;
  final HeatmapElementNode? parent;
  final bool masked;
  final bool deadEligible;

  bool get contributes {
    if (masked) return true;
    final id = anchor;
    if (id != null && isSafeAnchor(id)) return true;
    if (label != null && label!.isNotEmpty) return true;
    return role != 'node' && role != 'text';
  }
}

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

/// Short name safe to store on a heatmap element. Rejects emails, raw field
/// values that are only numbers, and long paragraphs.
String? safeHeatmapLabel(String? raw) {
  if (raw == null) return null;
  var text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty || text.length > 48) return null;
  if (_email.hasMatch(text)) return null;
  if (RegExp(r'^[\d\s.,:+\-/%#]+$').hasMatch(text)) return null;
  text = text.replaceAll(_longDigits, '#');
  text = text.replaceAll(RegExp(r'[/:#]'), ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty || !RegExp(r'[A-Za-z]').hasMatch(text)) return null;
  return text;
}

String _segment(HeatmapElementNode node) {
  final anchor = node.anchor;
  if (anchor != null && isSafeAnchor(anchor)) return anchor.trim();
  final label = node.label;
  if (label != null && label.isNotEmpty) {
    final base = '${node.role}:$label';
    return node.siblingIndex == 0 ? base : '$base#${node.siblingIndex}';
  }
  return '${node.role}:${node.siblingIndex}';
}

/// A mask container owns every tap inside it. Otherwise the path is this
/// control: an anchor id, or `role:label`. Wrapper nodes are not prefixed.
String buildElementPath(HeatmapElementNode node) {
  HeatmapElementNode? current = node;
  while (current != null) {
    if (current.masked && current.contributes) {
      final path = _segment(current);
      return path.length > maxPathLength
          ? path.substring(0, maxPathLength)
          : path;
    }
    current = current.parent;
  }

  final anchor = node.anchor;
  if (anchor != null && isSafeAnchor(anchor)) return anchor.trim();
  if (!node.contributes) return 'node:0';
  final path = _segment(node);
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
