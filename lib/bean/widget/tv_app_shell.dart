import 'dart:async';
import 'package:kazumi/services/platform/owned_method_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/widget/tv_focus_navigation.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/platform/tv_navigation.dart';
import 'package:kazumi/services/platform/app_remote.dart';
import 'package:kazumi/bean/widget/tv_artwork.dart';
import 'package:kazumi/bean/widget/tv_visuals.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/performance/tv_input_lifecycle.dart';

/// Applies TV-only focus behavior while preserving the normal mobile theme.
class TvAppShell extends StatefulWidget {
  const TvAppShell({super.key, required this.child});

  final Widget child;

  @override
  State<TvAppShell> createState() => _TvAppShellState();
}

class _TvAppShellState extends State<TvAppShell> {
  AppRemoteLease? _remoteLease;
  static const _channel = MethodChannel('com.predidit.kazumi/tv_navigation');
  static final _navigationOwners = OwnedMethodChannel(_channel,
      onActiveChanged: (_) => unawaited(_syncNavigationActive()));
  MethodChannelLease? _navigationLease;

  static Future<void> _syncNavigationActive() async {
    try {
      await _channel.invokeMethod<void>(
          'setActive', _navigationOwners.hasOwners);
    } on MissingPluginException {
      // audio_service can start Dart before MainActivity registers this channel.
      // Native sends ready after registration; no polling or stale retry timer.
    } on PlatformException catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
          exception: error, stack: stack, library: 'TV navigation handshake'));
    }
  }

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_handleConfirmRepeat);
    if (TvMode.enabled) {
      _remoteLease = AppRemote.instance.attachShell();
      _navigationLease = _navigationOwners.claim((call) async {
        if (call.method == 'ready') {
          await _syncNavigationActive();
          return;
        }
        if (TvInputLifecycle.active)
          TvInputLifecycle.platformAction(call.method, 'dart_received');
        if (call.method == 'home') TvNavigation.goHome();
        if (call.method == 'back') {
          final didPop = await rootNavigatorKey.currentState?.maybePop();
          if (TvInputLifecycle.active)
            TvInputLifecycle.platformAction('back', 'maybe_pop_result',
                didPop: didPop);
        }
      });
    }
  }

  // Material Activate shortcuts accept repeats by default. The initial press
  // may already have pushed a route, so guard at the TV shell above Navigator.
  KeyEventResult _handleConfirmRepeat(KeyEvent event) {
    if (!TvMode.enabled || event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    return key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.gameButtonA
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _remoteLease?.release();
    FocusManager.instance.removeEarlyKeyEventHandler(_handleConfirmRepeat);
    _navigationLease?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!TvMode.enabled) {
      return widget.child;
    }

    final theme = Theme.of(context);
    final oled = GStorage.getSetting(SettingsKeys.oledEnhance) &&
        theme.brightness == Brightness.dark;
    return Theme(
      data: TvVisuals.theme(theme, oled: oled),
      child: FocusTraversalGroup(
        policy: TvLoopTraversalPolicy(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (TvVisuals.fixedSurfaces)
              ColoredBox(
                  color: oled ? Colors.black : theme.scaffoldBackgroundColor)
            else
              TvAmbientBackdrop(oled: oled),
            widget.child,
          ],
        ),
      ),
    );
  }
}
