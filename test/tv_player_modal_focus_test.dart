import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/tv_player_focus.dart';
import 'package:kazumi/bean/dialog/adaptive_bottom_sheet.dart';

void main() {
  testWidgets('late panel hide cannot reclaim focus from a real modal sheet',
      (tester) async {
    final player = FocusNode(), first = FocusNode(), second = FocusNode();
    addTearDown(player.dispose);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    late BuildContext playerContext;
    final reclaimed = <bool>[];
    var actions = 0;
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        home: Builder(builder: (context) {
          playerContext = context;
          return Scaffold(
              body: TextButton(
                  focusNode: player,
                  onPressed: () {
                    Timer(
                        const Duration(seconds: 3),
                        () => reclaimed
                            .add(requestPlayerFocusIfCurrent(context, player)));
                    showAdaptiveBottomSheet<void>(
                        context: context,
                        builder: (_) =>
                            Column(mainAxisSize: MainAxisSize.min, children: [
                              TextButton(
                                  focusNode: first,
                                  autofocus: true,
                                  onPressed: () => actions++,
                                  child: const Text('First')),
                              TextButton(
                                  focusNode: second,
                                  onPressed: () => actions++,
                                  child: const Text('Second')),
                            ]));
                  },
                  child: const Text('Player')));
        })));
    player.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(first.hasPrimaryFocus, isTrue);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(reclaimed, [false]);
    expect(first.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(second.hasPrimaryFocus, isTrue);
    expect(actions, 0);
    await nav.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(requestPlayerFocusIfCurrent(playerContext, player), isTrue);
    await tester.pump();
    expect(player.hasPrimaryFocus, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
