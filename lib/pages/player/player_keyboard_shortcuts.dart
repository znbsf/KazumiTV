import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/platform/owned_method_channel.dart';

typedef PlayerShortcutAction = FutureOr<void> Function();
typedef PlayerNavigationKeyHandler = bool Function(LogicalKeyboardKey key);

class PlayerLongPressShortcutActions {
  const PlayerLongPressShortcutActions({
    required this.onRepeat,
    required this.onRelease,
    required this.onCancel,
  });

  final PlayerShortcutAction onRepeat;
  final PlayerShortcutAction onRelease;
  final PlayerShortcutAction onCancel;
}

/// Dispatches player shortcuts before focused controls handle the key event.
///
/// [focusScopeNode] must be attached to a stable ancestor of the player area.
/// Dialog routes and explicitly blocked overlay interactions keep their normal
/// key handling. Only a genuine release inside the owning context commits a
/// tap. Context loss, synthesized events and disposal cancel the hold.
class PlayerKeyboardShortcuts extends StatefulWidget {
  const PlayerKeyboardShortcuts({
    super.key,
    required this.focusScopeNode,
    required this.actions,
    this.longPressActions = const <String, PlayerLongPressShortcutActions>{},
    this.isBlocked,
    this.shouldHandleAction,
    this.onNavigationKey,
    this.shortcuts,
  });

  final FocusNode focusScopeNode;
  final Map<String, PlayerShortcutAction> actions;
  final Map<String, PlayerLongPressShortcutActions> longPressActions;
  final bool Function()? isBlocked;
  final bool Function(String actionName, LogicalKeyboardKey key)?
      shouldHandleAction;
  final PlayerNavigationKeyHandler? onNavigationKey;
  final Map<String, List<String>>? shortcuts;

  @override
  State<PlayerKeyboardShortcuts> createState() =>
      _PlayerKeyboardShortcutsState();
}

class _PlayerKeyboardShortcutsState extends State<PlayerKeyboardShortcuts>
    with WidgetsBindingObserver {
  static const _tvRemoteChannel = MethodChannel(
    'com.predidit.kazumi/tv_remote',
  );
  static final _tvRemoteOwners = OwnedMethodChannel(_tvRemoteChannel,
      onActiveChanged: (active) => unawaited(_tvRemoteChannel
          .invokeMethod<void>('setPlayerActive', {'active': active})));
  MethodChannelLease? _tvRemoteLease;
  late Map<String, List<String>> _shortcuts;
  final _activeLongPressKeys = <LogicalKeyboardKey,
      ({String actionName, PlayerLongPressShortcutActions actions})>{};
  ModalRoute<dynamic>? _route;
  bool _routeCovered = false;
  bool _applicationActive = true;

  @override
  void initState() {
    super.initState();
    _shortcuts = widget.shortcuts ?? _loadShortcuts();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _applicationActive =
        lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_cancelInvalidLongPressShortcuts);
    FocusManager.instance.addEarlyKeyEventHandler(_handleKeyEvent);
    if (TvMode.enabled) {
      _tvRemoteLease = _tvRemoteOwners.claim(_handleTvRemoteMethod);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _routeCovered = RouteVisibility.isCoveredOf(context);
    _cancelInvalidLongPressShortcuts();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _applicationActive = state == AppLifecycleState.resumed;
    if (!_applicationActive) _cancelAllLongPressShortcuts();
  }

  @override
  void didUpdateWidget(PlayerKeyboardShortcuts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shortcuts != oldWidget.shortcuts ||
        widget.focusScopeNode != oldWidget.focusScopeNode) {
      _cancelAllLongPressShortcuts();
      _shortcuts = widget.shortcuts ?? _loadShortcuts();
    }
    _cancelInvalidLongPressShortcuts();
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleKeyEvent);
    FocusManager.instance.removeListener(_cancelInvalidLongPressShortcuts);
    WidgetsBinding.instance.removeObserver(this);
    _tvRemoteLease?.release();
    _cancelAllLongPressShortcuts();
    super.dispose();
  }

  Future<void> _handleTvRemoteMethod(MethodCall call) async {
    if (call.method != 'dispatch' || call.arguments is! String) return;
    final actionName = call.arguments as String;
    if (widget.isBlocked?.call() ?? false) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    final action = widget.actions[actionName];
    if (action != null) await _runAction(action);
  }

  Map<String, List<String>> _loadShortcuts() {
    final shortcuts = <String, List<String>>{
      for (final entry in defaultShortcuts.entries)
        entry.key: GStorage.getStringListSettingByName(
          'shortcut_${entry.key}',
          defaultValue: entry.value,
        ),
    };
    return TvMode.enabled ? withTvRemoteShortcuts(shortcuts) : shortcuts;
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    // A release can arrive before a focus/route notification. Check ownership
    // first, so it cannot commit an armed short tap after the context changed.
    _cancelInvalidLongPressShortcuts();
    if (event.synthesized) {
      final active = _activeLongPressKeys.remove(event.logicalKey);
      if (active != null) _invokeCancellation(active.actions.onCancel);
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) {
      final longPressActions = _activeLongPressKeys.remove(event.logicalKey);
      if (longPressActions != null) {
        _invokeAction(longPressActions.actions.onRelease);
        return KeyEventResult.handled;
      }
    }

    if (!_shouldHandleShortcut()) {
      return KeyEventResult.ignored;
    }

    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        (widget.onNavigationKey?.call(event.logicalKey) ?? false)) {
      return KeyEventResult.handled;
    }

    final keyLabel = event.logicalKey.keyLabel.isNotEmpty
        ? event.logicalKey.keyLabel
        : event.logicalKey.debugName ?? '';
    final actionName = _findActionName(keyLabel);
    if (actionName == null) {
      return KeyEventResult.ignored;
    }
    if (!(widget.shouldHandleAction?.call(actionName, event.logicalKey) ??
        true)) {
      return KeyEventResult.ignored;
    }

    if (event is KeyDownEvent) {
      final action = widget.actions[actionName];
      if (action == null) {
        return KeyEventResult.ignored;
      }
      final longPressActions = widget.longPressActions[actionName];
      if (longPressActions != null) {
        // Aliases of forward share one business hold and saved base speed.
        // Finish the previous owner before arming another key.
        _cancelAllLongPressShortcuts();
        _activeLongPressKeys[event.logicalKey] =
            (actionName: actionName, actions: longPressActions);
      }
      _invokeAction(action);
      return KeyEventResult.handled;
    }

    if (event is KeyRepeatEvent) {
      final longPressActions = _activeLongPressKeys[event.logicalKey];
      if (longPressActions == null) {
        return KeyEventResult.ignored;
      }
      _invokeAction(longPressActions.actions.onRepeat);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  bool _shouldHandleShortcut() {
    if (!_applicationActive || _routeCovered) return false;
    if (widget.isBlocked?.call() ?? false) {
      return false;
    }

    if (_route != null && !_route!.isCurrent) {
      return false;
    }

    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus == null ||
        (primaryFocus != widget.focusScopeNode &&
            !primaryFocus.ancestors.contains(widget.focusScopeNode))) {
      return false;
    }

    final focusContext = primaryFocus.context;
    if (focusContext == null) {
      return true;
    }
    return focusContext.widget is! EditableText &&
        focusContext.findAncestorWidgetOfExactType<EditableText>() == null;
  }

  String? _findActionName(String keyLabel) {
    for (final entry in _shortcuts.entries) {
      if (entry.value.contains(keyLabel)) {
        return entry.key;
      }
    }
    return null;
  }

  void _cancelInvalidLongPressShortcuts() {
    if (_activeLongPressKeys.isEmpty) return;
    if (!_shouldHandleShortcut()) {
      _cancelAllLongPressShortcuts();
      return;
    }
    for (final entry in _activeLongPressKeys.entries.toList()) {
      if (!(widget.shouldHandleAction
              ?.call(entry.value.actionName, entry.key) ??
          true)) {
        _activeLongPressKeys.remove(entry.key);
        _invokeCancellation(entry.value.actions.onCancel);
      }
    }
  }

  void _cancelAllLongPressShortcuts() {
    final actions = _activeLongPressKeys.values.map((v) => v.actions).toSet();
    // Clear synchronously before callbacks; late repeat/UP cannot finish twice.
    _activeLongPressKeys.clear();
    for (final action in actions) {
      _invokeCancellation(action.onCancel);
    }
  }

  void _invokeCancellation(PlayerShortcutAction action) {
    // Route/widget updates can cancel while a descendant is building. The
    // hold is already removed; let the callback update the HUD after build.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      scheduleMicrotask(() => _invokeAction(action));
    } else {
      _invokeAction(action);
    }
  }

  void _invokeAction(PlayerShortcutAction action) {
    unawaited(_runAction(action));
  }

  Future<void> _runAction(PlayerShortcutAction action) async {
    try {
      await action();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'player keyboard shortcuts',
          context: ErrorDescription('while invoking a player shortcut'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Adds Android TV remote aliases without changing the user's stored mapping.
Map<String, List<String>> withTvRemoteShortcuts(
  Map<String, List<String>> source,
) {
  final result = <String, List<String>>{
    for (final entry in source.entries) entry.key: [...entry.value],
  };

  String label(LogicalKeyboardKey key) => key.keyLabel.isNotEmpty
      ? key.keyLabel
      : key.debugName ?? key.keyId.toString();

  void add(String action, LogicalKeyboardKey key) {
    final values = result.putIfAbsent(action, () => <String>[]);
    final keyLabel = label(key);
    if (!values.contains(keyLabel)) values.add(keyLabel);
  }

  result['volumeup']?.remove(label(LogicalKeyboardKey.arrowUp));
  result['volumedown']?.remove(label(LogicalKeyboardKey.arrowDown));
  result['exitfullscreen']?.remove(label(LogicalKeyboardKey.escape));

  for (final key in [
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
  ]) {
    add('showcontrols', key);
  }
  add('playorpause', LogicalKeyboardKey.mediaPlayPause);
  add('play', LogicalKeyboardKey.mediaPlay);
  add('pause', LogicalKeyboardKey.mediaPause);
  add('forward', LogicalKeyboardKey.mediaFastForward);
  add('forward', LogicalKeyboardKey.mediaSkipForward);
  add('rewind', LogicalKeyboardKey.mediaRewind);
  add('rewind', LogicalKeyboardKey.mediaSkipBackward);
  add('next', LogicalKeyboardKey.mediaTrackNext);
  add('next', LogicalKeyboardKey.channelUp);
  add('prev', LogicalKeyboardKey.mediaTrackPrevious);
  add('prev', LogicalKeyboardKey.channelDown);
  add('prev', LogicalKeyboardKey.mediaLast);
  add('volumeup', LogicalKeyboardKey.audioVolumeUp);
  add('volumedown', LogicalKeyboardKey.audioVolumeDown);
  add('togglemute', LogicalKeyboardKey.audioVolumeMute);
  add('showepisodes', LogicalKeyboardKey.guide);
  add('showepisodes', LogicalKeyboardKey.mediaTopMenu);
  add('showepisodes', LogicalKeyboardKey.colorF2Yellow);
  add('toggledanmaku', LogicalKeyboardKey.closedCaptionToggle);
  add('toggledanmaku', LogicalKeyboardKey.mediaAudioTrack);
  add('toggledanmaku', LogicalKeyboardKey.colorF0Red);
  add('togglefavorite', LogicalKeyboardKey.browserFavorites);
  add('togglefavorite', LogicalKeyboardKey.favoriteStore0);
  add('togglefavorite', LogicalKeyboardKey.colorF1Green);
  add('showdetails', LogicalKeyboardKey.info);
  add('showdetails', LogicalKeyboardKey.colorF3Blue);
  add('showremotehelp', LogicalKeyboardKey.help);
  add('showremotehelp', LogicalKeyboardKey.contextMenu);
  add('showremotehelp', LogicalKeyboardKey.f1);
  add('back', LogicalKeyboardKey.goBack);
  add('back', LogicalKeyboardKey.escape);
  add('back', LogicalKeyboardKey.gameButtonB);
  add('exitplayer', LogicalKeyboardKey.exit);
  add('exitplayer', LogicalKeyboardKey.close);
  add('exitplayer', LogicalKeyboardKey.mediaClose);
  add('exitplayer', LogicalKeyboardKey.mediaStop);
  return result;
}

bool shouldDeferTvKeyToPlatform(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.audioVolumeUp ||
      key == LogicalKeyboardKey.audioVolumeDown ||
      key == LogicalKeyboardKey.audioVolumeMute;
}
