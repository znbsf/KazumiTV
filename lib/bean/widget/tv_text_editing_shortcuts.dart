import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

/// Lets TV users leave an explicit editor to reach its actions.
/// Horizontal cursor movement, IME actions and non-TV editing stay native.
class TvTextEditingShortcuts extends StatelessWidget {
  const TvTextEditingShortcuts({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!TvMode.enabled) return child;
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
      },
      child: child,
    );
  }
}
