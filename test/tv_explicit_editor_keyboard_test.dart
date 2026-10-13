import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/tv_search_entry.dart';
import 'package:kazumi/pages/video/episode_jump_dialog.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
  await tester.pump();
}

void main() {
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() => TvMode.setEnabledForTesting(false));
  for (final cancel in [false, true]) {
    testWidgets('episode jump keyboard footer ${cancel ? 'cancel' : 'confirm'}',
        (tester) async {
      int? result = -1;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      autofocus: true,
                      onPressed: () async {
                        result =
                            await showEpisodeJumpDialog(context, count: 20);
                      },
                      child: const Text('open'))))));
      await tester.pumpAndSettle();
      await tester.pump();
      await _key(tester, LogicalKeyboardKey.enter);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.enterText(
          find.byKey(const ValueKey('episode-jump-number')), '7');
      final inputFocus = FocusManager.instance.primaryFocus;
      tester.testTextInput.hide();
      await _key(tester,
          cancel ? LogicalKeyboardKey.arrowDown : LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus, isNot(same(inputFocus)));
      expect(
          FocusManager.instance.primaryFocus!.context!
              .findAncestorWidgetOfExactType<TextButton>(),
          isNotNull);
      expect(result, -1);
      await _key(tester, LogicalKeyboardKey.enter);
      expect(find.byType(AlertDialog), findsNothing);
      expect(result, cancel ? isNull : 6);
    });
    testWidgets('search editor keyboard footer ${cancel ? 'cancel' : 'submit'}',
        (tester) async {
      final controller = TextEditingController(text: 'original');
      addTearDown(controller.dispose);
      final submitted = <String>[];
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: TvSearchEntry(
                  controller: controller, onSubmitted: submitted.add))));
      await tester.pumpAndSettle();
      await tester.pump();
      await _key(tester, LogicalKeyboardKey.enter);
      await tester.enterText(
          find.byKey(const Key('tv-search-editor')), 'draft');
      final inputFocus = FocusManager.instance.primaryFocus;
      tester.testTextInput.hide();
      await _key(tester,
          cancel ? LogicalKeyboardKey.arrowDown : LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus, isNot(same(inputFocus)));
      expect(submitted, isEmpty);
      await _key(tester, LogicalKeyboardKey.enter);
      expect(submitted, cancel ? isEmpty : ['draft']);
      expect(controller.text, 'original');
      expect(find.byType(AlertDialog), findsNothing);
    });
  }
  testWidgets('non TV episode editor preserves native arrows', (tester) async {
    TvMode.setEnabledForTesting(false);
    int? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    autofocus: true,
                    onPressed: () async {
                      result = await showEpisodeJumpDialog(context, count: 20);
                    },
                    child: const Text('open'))))));
    await tester.pumpAndSettle();
    await tester.pump();
    await _key(tester, LogicalKeyboardKey.enter);
    await tester.enterText(find.byType(TextField), '3');
    final inputFocus = FocusManager.instance.primaryFocus;
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus, same(inputFocus));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(result, isNull);
  });
}
