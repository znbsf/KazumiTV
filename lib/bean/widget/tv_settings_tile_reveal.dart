import 'package:flutter/material.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

/// Material reveals the focused Slider's render box, which excludes the
/// setting's label/value. Reveal the containing tile after that native move.
class TvSettingsTileReveal extends StatefulWidget {
  const TvSettingsTileReveal({super.key, required this.child});
  final Widget child;
  @override
  State<TvSettingsTileReveal> createState() => _TvSettingsTileRevealState();
}

class _TvSettingsTileRevealState extends State<TvSettingsTileReveal> {
  final _focus = FocusNode(canRequestFocus: false, skipTraversal: true);
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _reveal(bool focused) {
    if (!focused) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focus.hasFocus) return;
      // Each policy moves only when its edge is clipped. A fully visible tile
      // stays put. End first preserves the label if a very small viewport cannot
      // contain the entire tile; no animation races remote key repeats.
      Scrollable.ensureVisible(context,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
      Scrollable.ensureVisible(context,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart);
    });
  }

  @override
  Widget build(BuildContext context) => TvMode.enabled
      ? Focus(focusNode: _focus, onFocusChange: _reveal, child: widget.child)
      : widget.child;
}
