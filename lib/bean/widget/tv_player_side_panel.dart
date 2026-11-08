import 'package:flutter/material.dart';

/// Shared width for the episode panel and TV modal panels.
double tvPlayerSidePanelWidth(double screenWidth) =>
    (screenWidth * 0.42).clamp(360.0, 440.0).toDouble();

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
        color: Theme.of(context).colorScheme.surface.withValues(alpha: opacity),
        child: child,
      );
}
