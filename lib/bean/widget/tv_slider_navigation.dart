import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

/// Material Slider already supports left/right adjustment in directional mode.
/// Keep that native path (steps, RTL, callbacks and touch), but let vertical
/// input traverse the settings instead of adjusting the value. Scoped to actual
/// sliders, not the player or the whole application.
class TvSliderNavigation extends StatelessWidget {
  const TvSliderNavigation({super.key, required this.child});
  final Slider child;

  @override
  Widget build(BuildContext context) {
    if (!TvMode.enabled) return child;
    if (child.onChanged == null || child.min == child.max) {
      return ExcludeFocus(child: child);
    }
    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(navigationMode: NavigationMode.directional),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) {
          final direction = switch (event.logicalKey) {
            LogicalKeyboardKey.arrowUp => TraversalDirection.up,
            LogicalKeyboardKey.arrowDown => TraversalDirection.down,
            _ => null,
          };
          if (direction == null) return KeyEventResult.ignored;
          if (event is KeyDownEvent || event is KeyRepeatEvent) {
            FocusManager.instance.primaryFocus?.focusInDirection(direction);
          }
          // No target still means no adjustment, and no second parent action.
          return KeyEventResult.handled;
        },
        child: child,
      ),
    );
  }
}
