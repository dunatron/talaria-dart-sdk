import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'element_path.dart';
import 'markers.dart';
import 'privacy.dart';

/// A tappable control discovered in the widget tree.
class HeatmapTarget {
  const HeatmapTarget({
    required this.path,
    required this.role,
    required this.globalRect,
    required this.localRect,
    required this.deadEligible,
    this.label,
  });

  final String path;
  final String role;
  final String? label;
  final Rect globalRect;
  final Rect localRect;
  final bool deadEligible;

  double get area => globalRect.width * globalRect.height;
}

class HeatmapTree {
  const HeatmapTree(this.nodes);

  final List<HeatmapTarget> nodes;

  /// Smallest interactive control under [global], otherwise the smallest node.
  HeatmapTarget? hit(Offset global) {
    HeatmapTarget? bestInteractive;
    HeatmapTarget? bestOther;
    var bestInteractiveArea = double.infinity;
    var bestOtherArea = double.infinity;
    for (final node in nodes) {
      if (!node.globalRect.contains(global)) continue;
      if (_interactive(node.role)) {
        if (node.area < bestInteractiveArea) {
          bestInteractive = node;
          bestInteractiveArea = node.area;
        }
      } else if (node.area < bestOtherArea) {
        bestOther = node;
        bestOtherArea = node.area;
      }
    }
    return bestInteractive ?? bestOther;
  }

  /// Nodes that intersect the snapshot, capped so the manifest stays small.
  /// Prefer anchored / interactive controls over unlabeled text when trimming.
  List<HeatmapTarget> forManifest(Size viewport) {
    final visible = [
      for (final node in nodes)
        if (node.localRect.overlaps(Offset.zero & viewport)) node,
    ];
    if (visible.length <= 200) return visible;
    final ranked = [...visible]..sort((a, b) {
        final aKeep = _manifestKeepScore(a);
        final bKeep = _manifestKeepScore(b);
        if (aKeep != bKeep) return bKeep.compareTo(aKeep);
        return b.area.compareTo(a.area);
      });
    while (ranked.length > 200) {
      ranked.removeAt(0);
    }
    return ranked;
  }
}

int _manifestKeepScore(HeatmapTarget node) {
  // Higher = keep when trimming. Anchors and interactive first.
  if (node.path.isNotEmpty && !node.path.contains(':') && node.path != 'node') {
    return 4; // likely an anchor / semantics identifier
  }
  if (_interactive(node.role)) return 3;
  if (node.role == 'heading') return 2;
  if (node.role == 'text' || node.role == 'node') return 0;
  return 1;
}

/// Walks the Element tree for heatmap targets.
///
/// [includeText] is false on the tap hot path (interactive / Semantics only)
/// and true when building the idle structural manifest.
HeatmapTree collectHeatmapTree(
  Element root,
  RenderBox boundary, {
  bool includeText = true,
}) {
  final origin = boundary.localToGlobal(Offset.zero);
  final viewport = boundary.hasSize ? boundary.size : Size.zero;
  final seen = <String, int>{};
  final nodes = <HeatmapTarget>[];

  void visit(
    Element element,
    HeatmapElementNode? parent, {
    required bool underInteractive,
  }) {
    final widget = element.widget;
    var nextParent = parent;
    var nextInteractive = underInteractive;
    final isAnchor = widget is TalariaHeatmapAnchor;
    final isSemantics = widget is Semantics;
    final isMask = widget is TalariaMask;
    final isField = widget is EditableText;
    final isText = includeText && widget is Text;

    if (isAnchor || isSemantics || isMask || isField || isText) {
      final box = element.renderObject;
      if (box is RenderBox && box.hasSize && box.attached) {
        final globalTop = box.localToGlobal(Offset.zero);
        final globalRect = globalTop & box.size;
        final localRect = (globalTop - origin) & box.size;
        final props = isSemantics ? widget.properties : null;
        final anchor = isAnchor
            ? widget.id
            : isSemantics
                ? props?.identifier
                : null;
        if (globalRect.width >= 2 &&
            globalRect.height >= 2 &&
            !_tooBig(localRect, viewport, anchored: anchor != null)) {
          var role = isMask
              ? 'node'
              : isText
                  ? 'text'
                  : _role(props, isField: isField);
          var label = _labelFor(element, widget, props, role);
          if ((role == 'node' || role == 'heading') && label != null) {
            // A heading keeps its role. A plain labeled node is text.
            if (role == 'node') role = 'text';
          }
          final masked = isMask;
          final node = HeatmapElementNode(
            anchor: anchor,
            role: role,
            label: label,
            siblingIndex: 0,
            parent: parent,
            masked: masked,
            deadEligible: role != 'textField' && role != 'slider',
          );
          final skipText =
              role == 'text' && (underInteractive || _insideTextField(element));
          if (node.contributes && !skipText) {
            final indexed = HeatmapElementNode(
              anchor: node.anchor,
              role: node.role,
              label: node.label,
              siblingIndex: _occurrence(seen, node),
              parent: parent,
              masked: node.masked,
              deadEligible: node.deadEligible,
            );
            nodes.add(
              HeatmapTarget(
                path: buildElementPath(indexed),
                role: indexed.role,
                label: indexed.label,
                globalRect: globalRect,
                localRect: localRect,
                deadEligible: indexed.deadEligible,
              ),
            );
            nextParent = indexed;
            nextInteractive = underInteractive ||
                _interactive(indexed.role) ||
                indexed.role == 'heading';
            if (masked) return;
          }
        }
      }
    }

    element.visitChildren(
      (child) => visit(child, nextParent, underInteractive: nextInteractive),
    );
  }

  visit(root, null, underInteractive: false);
  return HeatmapTree(nodes);
}

({List<Rect> covers, List<Rect> holes}) heatmapCoverRects({
  required Element root,
  required RenderBox boundary,
  required double ratio,
  required TalariaHeatmapPrivacy privacy,
}) {
  final origin = boundary.localToGlobal(Offset.zero);
  final covers = <Rect>[];
  final holes = <Rect>[];

  void visit(Element element, {required bool unmasked, required bool force}) {
    final widget = element.widget;
    final optedOut = unmasked || widget is TalariaUnmask;
    final inMask = (force || widget is TalariaMask) && !optedOut;
    final box = element.renderObject;
    if (box is RenderBox && box.hasSize && box.attached) {
      final rect = _scale(
        (box.localToGlobal(Offset.zero) - origin) & box.size,
        ratio,
      );
      if (widget is TalariaUnmask && force) holes.add(rect);
      if (inMask || _coverWidget(widget, privacy, optedOut: optedOut)) {
        covers.add(rect);
      }
    }
    element.visitChildren(
      (child) => visit(child, unmasked: optedOut, force: inMask),
    );
  }

  visit(root, unmasked: false, force: false);
  return (covers: covers, holes: holes);
}

bool _coverWidget(
  Widget widget,
  TalariaHeatmapPrivacy privacy, {
  required bool optedOut,
}) {
  if (optedOut) return false;
  if (widget is EditableText) {
    if (widget.obscureText) return true;
    return privacy.maskInputs;
  }
  if (privacy.maskText && (widget is Text || widget is RichText)) return true;
  if (privacy.maskImages && widget is Image) return true;
  return false;
}

bool _interactive(String role) {
  return role == 'button' ||
      role == 'link' ||
      role == 'textField' ||
      role == 'slider' ||
      role == 'checkbox' ||
      role == 'image';
}

bool _tooBig(Rect local, Size viewport, {required bool anchored}) {
  if (anchored || viewport.width <= 0 || viewport.height <= 0) return false;
  return local.width > viewport.width * 0.85 &&
      local.height > viewport.height * 0.85;
}

int _occurrence(Map<String, int> seen, HeatmapElementNode node) {
  final anchor = node.anchor;
  if (anchor != null && isSafeAnchor(anchor)) return 0;
  final label = node.label;
  final sig =
      label != null && label.isNotEmpty ? '${node.role}:$label' : node.role;
  final n = seen[sig] ?? 0;
  seen[sig] = n + 1;
  return n;
}

String _role(SemanticsProperties? props, {required bool isField}) {
  if (isField) return 'textField';
  if (props == null) return 'node';
  if (props.button == true) return 'button';
  if (props.link == true) return 'link';
  if (props.textField == true) return 'textField';
  if (props.slider == true) return 'slider';
  if (props.image == true) return 'image';
  if (props.header == true) return 'heading';
  if (props.checked != null || props.toggled != null) return 'checkbox';
  return 'node';
}

String? _labelFor(
  Element element,
  Widget widget,
  SemanticsProperties? props,
  String role,
) {
  if (widget is EditableText || role == 'textField') {
    return _fieldLabel(element) ??
        safeHeatmapLabel(props?.label ?? props?.hint);
  }
  final fromProps = safeHeatmapLabel(
    props?.label ?? props?.tooltip ?? props?.hint,
  );
  if (fromProps != null) return fromProps;
  if (widget is Text) return _textLabel(widget);
  if (_interactive(role) || role == 'node' || role == 'heading') {
    return _descendantText(element) ??
        _descendantTooltip(element) ??
        _ancestorTooltip(element);
  }
  return null;
}

String? _textLabel(Text text) {
  final data = text.data;
  if (data != null) return safeHeatmapLabel(data);
  return safeHeatmapLabel(text.textSpan?.toPlainText());
}

String? _descendantText(Element element) {
  String? found;
  void visit(Element current) {
    if (found != null) return;
    final widget = current.widget;
    if (widget is EditableText || widget is TextField) return;
    if (widget is Text) {
      found = _textLabel(widget);
      if (found != null) return;
    }
    current.visitChildren(visit);
  }

  element.visitChildren(visit);
  return found;
}

String? _fieldLabel(Element element) {
  String? label;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is TextField) {
      final decoration = widget.decoration;
      label = safeHeatmapLabel(decoration?.labelText ?? decoration?.hintText);
      return false;
    }
    return true;
  });
  return label;
}

bool _insideTextField(Element element) {
  var inside = false;
  element.visitAncestorElements((ancestor) {
    if (ancestor.widget is TextField) {
      inside = true;
      return false;
    }
    return true;
  });
  return inside;
}

String? _descendantTooltip(Element element) {
  String? found;
  void visit(Element current) {
    if (found != null) return;
    final widget = current.widget;
    if (widget is Tooltip) {
      found = safeHeatmapLabel(widget.message);
      if (found != null) return;
    }
    current.visitChildren(visit);
  }

  element.visitChildren(visit);
  return found;
}

String? _ancestorTooltip(Element element) {
  String? tip;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is Tooltip) {
      tip = safeHeatmapLabel(widget.message);
      return false;
    }
    return true;
  });
  return tip;
}

Rect _scale(Rect rect, double ratio) => Rect.fromLTRB(
      rect.left * ratio,
      rect.top * ratio,
      rect.right * ratio,
      rect.bottom * ratio,
    );
