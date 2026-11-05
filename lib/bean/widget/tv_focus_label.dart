import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
    this.onlyWhenTruncated = false,
    this.preferBelow = false,
  });

  final String message;
  final Widget child;
  final bool enabled;

  /// Use the laid-out text, including button padding and text scaling.
  final bool onlyWhenTruncated;

  /// Keep grid labels out of the dialog title above the focused row.
  final bool preferBelow;

  @override
  State<TvFocusLabel> createState() => _TvFocusLabelState();
}

class _TvFocusLabelState extends State<TvFocusLabel> {
  final _overlay = OverlayPortalController();
  bool _focused = false;
  final _childKey = GlobalKey();

  bool _textIsTruncated() {
    bool truncated = false;
    void visit(RenderObject object) {
      if (object is RenderParagraph) {
        truncated |= object.didExceedMaxLines;
      } else {
        object.visitChildren(visit);
      }
    }

    final render = _childKey.currentContext?.findRenderObject();
    if (render != null) visit(render);
    return truncated;
  }

  void _updateOverlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_focused &&
          widget.enabled &&
          TvMode.enabled &&
          (!widget.onlyWhenTruncated || _textIsTruncated())) {
        _overlay.show();
      } else {
        _overlay.hide();
      }
    });
  }

  void _onFocusChange(bool focused) {
    _focused = focused;
    _updateOverlay();
  }

  @override
  Widget build(BuildContext context) {
    if (!TvMode.enabled || !widget.enabled) return widget.child;
    if (_focused && widget.onlyWhenTruncated) _updateOverlay();
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
                  delegate: _LabelPosition(target, padding, widget.preferBelow),
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
        child: widget.onlyWhenTruncated
            ? KeyedSubtree(key: _childKey, child: widget.child)
            : widget.child,
      ),
    );
  }
}

class _LabelPosition extends SingleChildLayoutDelegate {
  const _LabelPosition(this.target, this.padding, this.preferBelow);
  final Rect target;
  final EdgeInsets padding;
  final bool preferBelow;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.max(
            0, math.min(360, constraints.maxWidth - padding.horizontal - 16)),
        maxHeight: math.max(
            0,
            constraints.maxHeight -
                padding.bottom -
                8 -
                (preferBelow
                    ? math.max(padding.top + 8, target.top)
                    : padding.top + 8)),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = padding.left + 8;
    final top =
        preferBelow ? math.max(padding.top + 8, target.top) : padding.top + 8;
    final right =
        math.max(left, size.width - padding.right - 8 - childSize.width);
    final bottom =
        math.max(top, size.height - padding.bottom - 8 - childSize.height);
    final above = target.top - childSize.height - 8;
    return Offset(
      (target.center.dx - childSize.width / 2).clamp(left, right),
      (preferBelow || above < top ? target.bottom + 8 : above)
          .clamp(top, bottom),
    );
  }

  @override
  bool shouldRelayout(_LabelPosition oldDelegate) =>
      target != oldDelegate.target ||
      padding != oldDelegate.padding ||
      preferBelow != oldDelegate.preferBelow;
}
