import 'package:flutter/material.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

/// Keeps the original InkWell focus target while painting inside its bounds.
class TvInkWell extends StatefulWidget {
  const TvInkWell({
    super.key,
    required this.onTap,
    this.child,
    this.focusNode,
    this.borderRadius = BorderRadius.zero,
    this.onHighlightChanged,
    this.overlayColor,
    this.builder,
    this.focusBackground = false,
    this.mobileBorderRadius,
  });

  final VoidCallback? onTap;
  final Widget? child;
  final FocusNode? focusNode;
  final BorderRadiusGeometry borderRadius;
  final ValueChanged<bool>? onHighlightChanged;
  final WidgetStateProperty<Color?>? overlayColor;
  final Widget Function(BuildContext, bool)? builder;
  final bool focusBackground;
  final BorderRadius? mobileBorderRadius;

  @override
  State<TvInkWell> createState() => _TvInkWellState();
}

class _TvInkWellState extends State<TvInkWell> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final focused = TvMode.enabled && _focused;
    final colors = Theme.of(context).colorScheme;
    final child = widget.builder?.call(context, focused) ?? widget.child;
    return InkWell(
      focusNode: widget.focusNode,
      onTap: widget.onTap,
      borderRadius: TvMode.enabled
          ? widget.borderRadius.resolve(Directionality.of(context))
          : widget.mobileBorderRadius,
      onHighlightChanged: widget.onHighlightChanged,
      overlayColor: widget.overlayColor,
      onFocusChange: (value) {
        if (TvMode.enabled && _focused != value) {
          setState(() => _focused = value);
        }
      },
      child: TvMode.enabled
          ? DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: widget.borderRadius,
                border: Border.all(
                  color: focused ? colors.primary : Colors.transparent,
                  width: 3,
                ),
              ),
              child: ColoredBox(
                color: widget.focusBackground && focused
                    ? colors.primary
                    : Colors.transparent,
                child: child,
              ),
            )
          : child,
    );
  }
}
