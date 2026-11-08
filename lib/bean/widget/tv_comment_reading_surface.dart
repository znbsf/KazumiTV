import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

/// A remote reading stop. Read oversized cards before traversing to a neighbour.
class TvCommentReadingSurface extends StatefulWidget {
  const TvCommentReadingSurface({
    super.key,
    required this.child,
    this.onPressed,
    this.borderRadius = 24,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final double borderRadius;

  @override
  State<TvCommentReadingSurface> createState() =>
      _TvCommentReadingSurfaceState();
}

class _TvCommentReadingSurfaceState extends State<TvCommentReadingSurface> {
  bool _focused = false;
  double? _readingOffset;

  Rect _bounds(RenderBox box) => box.localToGlobal(Offset.zero) & box.size;

  void _focusChanged(bool focused) {
    setState(() => _focused = focused);
    if (!focused) {
      _readingOffset = Scrollable.maybeOf(context)?.position.pixels;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focused) return;
      final scrollable = Scrollable.maybeOf(context);
      final card = context.findRenderObject();
      final viewport = scrollable?.context.findRenderObject();
      if (card is! RenderBox || viewport is! RenderBox) return;
      final cardRect = _bounds(card);
      final viewportRect = _bounds(viewport);
      // Closing a fragment menu must preserve the paragraph being read.
      if (_readingOffset == scrollable?.position.pixels &&
          cardRect.overlaps(viewportRect)) {
        return;
      }
      // Arriving from below must reveal the bottom of a tall previous card;
      // arriving from above must begin at its top.
      Scrollable.ensureVisible(context,
          alignment: cardRect.top < viewportRect.top ? 1 : 0,
          duration: const Duration(milliseconds: 100));
    });
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final down = key == LogicalKeyboardKey.arrowDown;
    final up = key == LogicalKeyboardKey.arrowUp;
    if (down || up) {
      final scrollable = Scrollable.maybeOf(context);
      final card = context.findRenderObject();
      final viewport = scrollable?.context.findRenderObject();
      if (scrollable != null && card is RenderBox && viewport is RenderBox) {
        final position = scrollable.position;
        final cardRect = _bounds(card);
        final viewportRect = _bounds(viewport);
        final remaining = down
            ? cardRect.bottom - viewportRect.bottom
            : viewportRect.top - cardRect.top;
        if (remaining > 1 &&
            (down
                ? position.pixels < position.maxScrollExtent
                : position.pixels > position.minScrollExtent)) {
          final step = remaining.clamp(0.0, position.viewportDimension * .65);
          position.jumpTo((position.pixels + (down ? step : -step))
              .clamp(position.minScrollExtent, position.maxScrollExtent));
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA) {
      if (event is KeyDownEvent) widget.onPressed?.call();
      return KeyEventResult.handled;
    }
    // Back belongs to the containing panel/route.
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (!TvMode.enabled) return widget.child;
    return Focus(
      descendantsAreFocusable: false,
      descendantsAreTraversable: false,
      onFocusChange: _focusChanged,
      onKeyEvent: _key,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(
            color: _focused
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 3,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}
