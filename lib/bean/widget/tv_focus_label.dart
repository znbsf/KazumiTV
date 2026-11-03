import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/tv_visuals.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

/// Names an icon on remote focus without changing its size or focus target.
/// Keep the button's Tooltip for pointer input and accessibility.
class TvFocusLabel extends StatefulWidget {
  const TvFocusLabel({
    super.key,
    required this.message,
    required this.child,
    this.enabled = true,
  });

  final String message;
  final Widget child;
  final bool enabled;

  @override
  State<TvFocusLabel> createState() => _TvFocusLabelState();
}

class _TvFocusLabelState extends State<TvFocusLabel> {
  final _overlay = OverlayPortalController();
  bool _focused = false;

  void _onFocusChange(bool focused) {
    _focused = focused;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_focused && widget.enabled && TvMode.enabled) {
        _overlay.show();
      } else {
        _overlay.hide();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!TvMode.enabled || !widget.enabled) return widget.child;
    // The overlay lives above the page and has a different MediaQuery.
    final padding = MediaQuery.paddingOf(context);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: _onFocusChange,
      child: OverlayPortal.overlayChildLayoutBuilder(
        controller: _overlay,
        overlayChildBuilder: (context, info) {
          final target = MatrixUtils.transformRect(
              info.childPaintTransform, Offset.zero & info.childSize);
          final colors = Theme.of(context).colorScheme;
          return IgnorePointer(
            child: ExcludeFocus(
              child: ExcludeSemantics(
                child: CustomSingleChildLayout(
                  delegate: _LabelPosition(target, padding),
                  child: Material(
                    color: colors.inverseSurface,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: Text(widget.message,
                          style: TvVisuals.control
                              .copyWith(color: colors.onInverseSurface)),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _LabelPosition extends SingleChildLayoutDelegate {
  const _LabelPosition(this.target, this.padding);
  final Rect target;
  final EdgeInsets padding;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.max(
            0, math.min(360, constraints.maxWidth - padding.horizontal - 16)),
        maxHeight: math.max(0, constraints.maxHeight - padding.vertical - 16),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = padding.left + 8;
    final top = padding.top + 8;
    final right =
        math.max(left, size.width - padding.right - 8 - childSize.width);
    final bottom =
        math.max(top, size.height - padding.bottom - 8 - childSize.height);
    final above = target.top - childSize.height - 8;
    return Offset(
      (target.center.dx - childSize.width / 2).clamp(left, right),
      (above >= top ? above : target.bottom + 8).clamp(top, bottom),
    );
  }

  @override
  bool shouldRelayout(_LabelPosition oldDelegate) =>
      target != oldDelegate.target || padding != oldDelegate.padding;
}
