import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/tv_visuals.dart';

/// A single translucent background. Children must not repaint canvasColor.
class TvPlayerSidePanel extends StatelessWidget {
  const TvPlayerSidePanel({
    super.key,
    required this.child,
    this.opacity = 0.64,
  });
  final Widget child;
  final double opacity;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: TvVisuals.surface.withValues(alpha: opacity),
        child: child,
      );
}
