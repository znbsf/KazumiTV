import 'package:flutter/material.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

/// Finite settings forms must expose both ends to remote traversal. A lazy
/// ListView only exposes its cache window, so Up can wrap into the middle.
/// Do not use this for dynamic content or unbounded user lists.
class BoundedSettingsScrollView extends StatelessWidget {
  const BoundedSettingsScrollView(
      {super.key, required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    if (!TvMode.enabled) return ListView(padding: padding, children: children);
    return SingleChildScrollView(
      padding: padding,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}
