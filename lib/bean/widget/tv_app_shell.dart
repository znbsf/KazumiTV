import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/widget/tv_focus_navigation.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/platform/tv_navigation.dart';
import 'package:kazumi/bean/widget/tv_artwork.dart';
import 'package:kazumi/bean/widget/tv_visuals.dart';
import 'package:kazumi/services/storage/storage.dart';

/// Applies TV-only focus behavior while preserving the normal mobile theme.
class TvAppShell extends StatefulWidget {
  const TvAppShell({super.key, required this.child});

  final Widget child;

  @override
  State<TvAppShell> createState() => _TvAppShellState();
}

class _TvAppShellState extends State<TvAppShell> {
  static const _channel = MethodChannel('com.predidit.kazumi/tv_navigation');

  @override
  void initState() {
    super.initState();
    if (TvMode.enabled) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'home') TvNavigation.goHome();
        if (call.method == 'back') {
          await rootNavigatorKey.currentState?.maybePop();
        }
      });
      _channel.invokeMethod<void>('setActive', true);
    }
  }

  @override
  void dispose() {
    if (TvMode.enabled) {
      _channel.setMethodCallHandler(null);
      _channel.invokeMethod<void>('setActive', false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!TvMode.enabled) {
      return widget.child;
    }

    final theme = Theme.of(context);
    final oled = GStorage.getSetting(SettingsKeys.oledEnhance);
    return Theme(
      data: TvVisuals.theme(theme, oled: oled),
      child: FocusTraversalGroup(
        policy: TvLoopTraversalPolicy(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (TvVisuals.fixedSurfaces)
              ColoredBox(color: oled ? Colors.black : TvVisuals.background)
            else
              TvAmbientBackdrop(oled: oled),
            widget.child,
          ],
        ),
      ),
    );
  }
}
