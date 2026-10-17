import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/navigation.dart';

/// A short app command, never an Android/system key injection.
class AppRemoteCommand {
  const AppRemoteCommand({required this.label, required this.invoke});
  final String label;
  final FutureOr<bool> Function() invoke;
}

class AppRemoteLease {
  AppRemoteLease(this._release);
  VoidCallback? _release;
  void release() {
    _release?.call();
    _release = null;
  }
}

class _Context {
  _Context(this.label, this.commands, this.priority);
  final String label;
  final Map<String, AppRemoteCommand> Function() commands;
  final int priority;
}

/// Only mounted application widgets expose capabilities. The transport submits
/// one tap with a context revision; it cannot address system keys or queue taps.
class AppRemote {
  AppRemote();
  static final instance = AppRemote();
  final List<_Context> _contexts = [];
  int _shells = 0;
  int _revision = 0;
  String? _signature;
  bool _busy = false;

  AppRemoteLease attachShell() {
    _shells++;
    return AppRemoteLease(() => _shells--);
  }

  AppRemoteLease register({
    required String label,
    required Map<String, AppRemoteCommand> Function() commands,
    int priority = 0,
  }) {
    final owner = _Context(label, commands, priority);
    _contexts.add(owner);
    return AppRemoteLease(() => _contexts.remove(owner));
  }

  static const _keys =
      <String, (String, LogicalKeyboardKey, PhysicalKeyboardKey)>{
    'up': ('上', LogicalKeyboardKey.arrowUp, PhysicalKeyboardKey.arrowUp),
    'down': ('下', LogicalKeyboardKey.arrowDown, PhysicalKeyboardKey.arrowDown),
    'left': ('左', LogicalKeyboardKey.arrowLeft, PhysicalKeyboardKey.arrowLeft),
    'right': (
      '右',
      LogicalKeyboardKey.arrowRight,
      PhysicalKeyboardKey.arrowRight
    ),
    'ok': ('确认', LogicalKeyboardKey.select, PhysicalKeyboardKey.enter),
    'back': ('返回', LogicalKeyboardKey.goBack, PhysicalKeyboardKey.escape),
  };

  ({String label, Map<String, AppRemoteCommand> commands}) _snapshot() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final node = FocusManager.instance.primaryFocus;
    final context = node?.context;
    final route = context == null ? null : ModalRoute.of(context);
    final enabled = _shells > 0 &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed) &&
        context != null &&
        context.mounted &&
        route?.isCurrent != false;
    final commands = <String, AppRemoteCommand>{};
    var label = '当前页面';
    if (enabled) {
      for (final entry in _keys.entries) {
        commands[entry.key] = AppRemoteCommand(
            label: entry.value.$1, invoke: () => _focusCommand(entry.key));
      }
      final owners = [..._contexts]
        ..sort((a, b) => a.priority.compareTo(b.priority));
      for (final owner in owners) {
        final offered = owner.commands();
        if (offered.isNotEmpty) {
          label = owner.label;
          for (final entry in offered.entries) {
            final fallback = commands[entry.key];
            commands[entry.key] = AppRemoteCommand(
                label: entry.value.label,
                invoke: () async {
                  if (await entry.value.invoke()) return true;
                  if (!identical(node, FocusManager.instance.primaryFocus) ||
                      !context.mounted ||
                      ModalRoute.of(context) != route) {
                    return false;
                  }
                  return await fallback?.invoke() ?? false;
                });
          }
        }
      }
    }
    final signature = '$enabled:${identityHashCode(node)}:'
        '${identityHashCode(route)}:$label:'
        '${commands.entries.map((e) => '${e.key}=${e.value.label}').join('|')}';
    if (signature != _signature) {
      _signature = signature;
      _revision++;
    }
    return (label: label, commands: commands);
  }

  Map<String, Object?> get state {
    final snapshot = _snapshot();
    return {
      'context': snapshot.label,
      'revision': _revision,
      'keys': [
        for (final entry in snapshot.commands.entries)
          {'id': entry.key, 'label': entry.value.label}
      ],
    };
  }

  Future<bool> dispatch(String id, {required int revision}) async {
    final snapshot = _snapshot();
    if (_busy || revision != _revision) return false;
    final command = snapshot.commands[id];
    if (command == null) return false;
    _busy = true;
    // Consume the revision before invoking: even synchronous route/focus
    // changes cannot permit a second tap from the same view of the app.
    _revision++;
    try {
      return await command.invoke();
    } finally {
      _busy = false;
    }
  }

  Future<bool> _focusCommand(String id) async {
    final node = FocusManager.instance.primaryFocus;
    final context = node?.context;
    if (node == null || context == null || !context.mounted) return false;
    final key = _keys[id];
    if (key == null) return false;
    final event = KeyDownEvent(
        physicalKey: key.$3, logicalKey: key.$2, timeStamp: Duration.zero);
    // Give real component handlers first refusal (sliders, episode panels,
    // recovery overlays). No HardwareKeyboard/platform global state is changed.
    for (final owner in [node, ...node.ancestors]) {
      final result = owner.onKeyEvent?.call(owner, event);
      if (result == KeyEventResult.handled) return true;
      if (result == KeyEventResult.skipRemainingHandlers) return false;
    }
    if (!context.mounted) return false;
    if (id == 'back') {
      return await rootNavigatorKey.currentState?.maybePop() ?? false;
    }
    final editor = context.widget is EditableText
        ? context.widget as EditableText
        : context.findAncestorWidgetOfExactType<EditableText>();
    if (editor != null) {
      // Editing text stays with the explicit editor. Vertical taps reach its
      // action buttons, horizontal taps move its local selection only.
      if (id == 'up') return node.previousFocus();
      if (id == 'down') return node.nextFocus();
      if (id == 'left' || id == 'right') {
        final value = editor.controller.value;
        final old = value.selection.isValid
            ? value.selection.extentOffset
            : value.text.length;
        final painter = TextPainter(
            text: TextSpan(text: value.text), textDirection: TextDirection.ltr);
        final offset = id == 'left'
            ? (painter.getOffsetBefore(old) ?? 0)
            : (painter.getOffsetAfter(old) ?? value.text.length);
        painter.dispose();
        editor.controller.selection = TextSelection.collapsed(offset: offset);
        return true;
      }
      return false; // OK must not submit a business action from text editing.
    }
    if (id == 'ok') {
      const intent = ActivateIntent();
      final action = Actions.maybeFind<ActivateIntent>(context);
      if (action == null || !action.isEnabled(intent)) return false;
      Actions.invoke(context, intent);
      return true;
    }
    final direction = switch (id) {
      'up' => TraversalDirection.up,
      'down' => TraversalDirection.down,
      'left' => TraversalDirection.left,
      'right' => TraversalDirection.right,
      _ => null,
    };
    return direction == null ? false : node.focusInDirection(direction);
  }
}
