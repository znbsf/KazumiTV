// These are widget callback-contract tests, not native rate/seek measurements.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';
import 'package:kazumi/pages/player/player_keyboard_shortcuts.dart';

String _label(LogicalKeyboardKey key) =>
    key.keyLabel.isNotEmpty ? key.keyLabel : key.debugName!;

class _Fixture {
  final scope = FocusScopeNode();
  final inside = FocusNode();
  final outside = FocusNode();
  final navigator = GlobalKey<NavigatorState>();
  late StateSetter rebuild;
  bool blocked = false;
  bool allowed = true;
  bool covered = false;
  VoidCallback? onCancelled;
  int downs = 0, repeats = 0, commits = 0, cancels = 0;
  late final shortcuts = {
    'forward': [
      _label(LogicalKeyboardKey.arrowRight),
      _label(LogicalKeyboardKey.mediaFastForward)
    ]
  };
  late final Map<String, PlayerShortcutAction> actions = {
    'forward': () => downs++,
  };
  late final longPress = {
    'forward': PlayerLongPressShortcutActions(
      onRepeat: () => repeats++,
      onRelease: () => commits++,
      onCancel: () {
        cancels++;
        onCancelled?.call();
      },
    ),
  };

  Future<void> mount(WidgetTester tester) async {
    addTearDown(scope.dispose);
    addTearDown(inside.dispose);
    addTearDown(outside.dispose);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        return RouteVisibility(
            isCovered: covered,
            child: Column(children: [
              FocusScope(
                  node: scope,
                  child: Column(children: [
                    PlayerKeyboardShortcuts(
                      focusScopeNode: scope,
                      shortcuts: shortcuts,
                      actions: actions,
                      longPressActions: longPress,
                      isBlocked: () => blocked,
                      shouldHandleAction: (_, __) => allowed,
                    ),
                    Focus(focusNode: inside, child: const SizedBox()),
                  ])),
              Focus(focusNode: outside, child: const SizedBox()),
            ]));
      }),
    ));
    inside.requestFocus();
    await tester.pump();
  }

  Future<void> refresh(WidgetTester tester) async {
    rebuild(() {});
    await tester.pump();
  }
}

void main() {
  testWidgets('route cancellation may update the owning player HUD safely',
      (tester) async {
    final f = _Fixture();
    await f.mount(tester);
    f.onCancelled = () => f.rebuild(() {});
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    f.blocked = true;
    await f.refresh(tester);
    await tester.pump();
    expect(f.cancels, 1);
    expect(tester.takeException(), isNull);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    expect(f.commits, 0);
  });
  testWidgets('genuine UP commits one armed short tap', (tester) async {
    final f = _Fixture();
    await f.mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect([f.downs, f.repeats, f.commits, f.cancels], [1, 0, 1, 0]);
  });

  for (final cause in [
    'focus',
    'blocked update',
    'action gate',
    'covered',
    'inactive'
  ]) {
    testWidgets('active repeat is cancelled once on $cause before another key',
        (tester) async {
      final f = _Fixture();
      await f.mount(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      switch (cause) {
        case 'focus':
          f.outside.requestFocus();
          await tester.pump();
        case 'blocked update':
          f.blocked = true;
          await f.refresh(tester);
        case 'action gate':
          f.allowed = false;
          await f.refresh(tester);
        case 'covered':
          f.covered = true;
          await f.refresh(tester);
        case 'inactive':
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      }
      expect([f.commits, f.cancels], [0, 1]);
      // Returning to the player does not re-arm the old physical hold.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      f.blocked = f.covered = false;
      f.allowed = true;
      await f.refresh(tester);
      f.inside.requestFocus();
      await tester.pump();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      expect([f.repeats, f.commits, f.cancels], [1, 0, 1]);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect([f.downs, f.commits, f.cancels], [2, 1, 1]);
    });
  }

  testWidgets('late UP rechecks a block without requiring rebuild',
      (tester) async {
    final f = _Fixture();
    await f.mount(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    f.blocked = true;
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    expect([f.commits, f.cancels], [0, 1]);
  });

  testWidgets('blocked repeat cancels instead of invoking another repeat',
      (tester) async {
    final f = _Fixture();
    await f.mount(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    f.blocked = true;
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    expect([f.repeats, f.commits, f.cancels], [1, 0, 1]);
  });

  testWidgets('a covering PopupRoute cancels even without moving focus',
      (tester) async {
    final f = _Fixture();
    await f.mount(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    unawaited(showDialog<void>(
      context: f.navigator.currentContext!,
      requestFocus: false,
      builder: (_) => const SizedBox(),
    ));
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, f.inside);
    expect([f.commits, f.cancels], [0, 1]);
    f.navigator.currentState!.pop();
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    expect([f.commits, f.cancels], [0, 1]);
  });

  testWidgets('synthesized UP cancels; later real UP cannot commit again',
      (tester) async {
    final f = _Fixture();
    await f.mount(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    // Isolate the app FocusManager path; the real UP below cleans hardware state.
    // ignore: deprecated_member_use
    tester.binding.keyEventManager.keyMessageHandler!(KeyMessage([
      const KeyUpEvent(
        logicalKey: LogicalKeyboardKey.arrowRight,
        physicalKey: PhysicalKeyboardKey.arrowRight,
        timeStamp: Duration.zero,
        synthesized: true,
      ),
    ], null));
    expect([f.commits, f.cancels], [0, 1]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    expect([f.commits, f.cancels], [0, 1]);
  });

  testWidgets('a second forward alias replaces the first hold owner',
      (tester) async {
    final f = _Fixture();
    await f.mount(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.mediaFastForward);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    expect([f.downs, f.commits, f.cancels], [2, 0, 1]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.mediaFastForward);
    expect([f.downs, f.commits, f.cancels], [2, 1, 1]);
  });
}
