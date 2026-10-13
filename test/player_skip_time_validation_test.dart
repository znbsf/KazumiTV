import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/dialog/dialog.dart';
import 'package:kazumi/pages/player/controller/player_playback_controller.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/player/player_item_panel.dart';
import 'package:kazumi/pages/player/smallest_player_item_panel.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

class _Playback implements PlayerPlaybackController {
  @override
  int buttonSkipTime = 80;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player implements PlayerController {
  @override
  final playback = _Playback();
  final writes = <int>[];
  @override
  void setButtonForwardTime(int value) {
    writes.add(value);
    playback.buttonSkipTime = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => TvMode.setEnabledForTesting(false));
  for (final entry in <String, void Function(PlayerController)>{
    'standard': showPlayerForwardTimeDialog,
    'small': showSmallestPlayerForwardTimeDialog,
  }.entries) {
    for (final tv in [true, false]) {
      testWidgets('${entry.key} skip invalid input stays editable tv=$tv',
          (tester) async {
        TvMode.setEnabledForTesting(tv);
        final player = _Player();
        await tester.pumpWidget(MaterialApp(
            navigatorObservers: [KazumiDialog.observer],
            home: Scaffold(
                body: TextButton(
                    autofocus: true,
                    onPressed: () => entry.value(player),
                    child: const Text('open')))));
        await tester.pumpAndSettle();
        await _key(tester, LogicalKeyboardKey.enter);
        Future<void> edit(String value) async {
          if (tv) {
            // Return from the action to the navigation entry after validation.
            if (find.byType(TextField).evaluate().isEmpty) {
              await _key(tester, LogicalKeyboardKey.arrowUp);
              await _key(tester, LogicalKeyboardKey.enter);
            }
          }
          await tester.enterText(find.byType(TextField), value);
          if (tv) {
            tester.testTextInput.hide();
            await _key(tester, LogicalKeyboardKey.arrowUp);
            await _key(tester, LogicalKeyboardKey.enter);
            await _key(tester, LogicalKeyboardKey.arrowDown);
            await _key(tester, LogicalKeyboardKey.arrowRight);
            await _key(tester, LogicalKeyboardKey.enter);
          } else {
            await tester.tap(find.text('确定'));
            await tester.pumpAndSettle();
          }
        }

        if (tv) await _key(tester, LogicalKeyboardKey.enter);
        for (final value in ['9' * 100, '0']) {
          await edit(value);
          expect(tester.takeException(), isNull);
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(player.writes, isEmpty);
          expect(player.playback.buttonSkipTime, 80);
        }
        await edit('25');
        expect(find.byType(AlertDialog), findsNothing);
        expect(player.writes, [25]);
      });
    }
    testWidgets('${entry.key} empty confirmation preserves old value',
        (tester) async {
      TvMode.setEnabledForTesting(false);
      final player = _Player();
      await tester.pumpWidget(MaterialApp(
          navigatorObservers: [KazumiDialog.observer],
          home: Scaffold(
              body: TextButton(
                  onPressed: () => entry.value(player),
                  child: const Text('open')))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(player.writes, isEmpty);
      expect(player.playback.buttonSkipTime, 80);
    });
  }
}
