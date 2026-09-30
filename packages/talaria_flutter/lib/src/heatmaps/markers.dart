import 'package:flutter/widgets.dart';

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

/// Always covered in snapshots. Taps inside are attributed to this container.
class TalariaMask extends StatelessWidget {
  const TalariaMask({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Opts a subtree out of snapshot covers, including password fields.
class TalariaUnmask extends StatelessWidget {
  const TalariaUnmask({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
