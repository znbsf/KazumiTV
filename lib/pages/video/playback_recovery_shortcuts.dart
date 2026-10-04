import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Loading/error surfaces outlive PlayerItem and its playback shortcuts.
class PlaybackRecoveryShortcuts extends StatelessWidget {
  const PlaybackRecoveryShortcuts({
    super.key,
    required this.enabled,
    required this.onBack,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
        skipTraversal: true,
        onKeyEvent: (_, event) {
          if (!enabled ||
              !const [
                LogicalKeyboardKey.escape,
                LogicalKeyboardKey.goBack,
                LogicalKeyboardKey.gameButtonB
              ].contains(event.logicalKey)) {
            return KeyEventResult.ignored;
          }
          if (event is KeyDownEvent) onBack();
          return KeyEventResult.handled;
        },
        child: child,
      );
}
