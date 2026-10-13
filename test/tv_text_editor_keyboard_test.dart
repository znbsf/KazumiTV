import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/tv_text_entry.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

void main() {
  tearDown(() => TvMode.setEnabledForTesting(false));
  for (final cancel in [false, true]) {
    testWidgets(
        'multiline keyboard ${cancel ? 'cancel' : 'confirm'} after IME hides',
        (tester) async {
      TvMode.setEnabledForTesting(true);
      final controller = TextEditingController(text: 'original');
      final entry = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(entry.dispose);
      var changes = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: TvTextEntry(
        child: TextField(
            controller: controller,
            focusNode: entry,
            maxLines: 8,
            onChanged: (_) => changes++),
      ))));
      entry.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      final editor = find.byKey(const Key('tv-text-editor'));
      await tester.enterText(editor, 'first\nsecond');
      await tester.testTextInput.receiveAction(TextInputAction.newline);
      await tester.pump();
      expect(editor, findsOneWidget);
      expect(controller.text, 'original');
      final editFocus = FocusManager.instance.primaryFocus;
      tester.testTextInput.hide();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, same(editFocus));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, same(editFocus));
      await tester.sendKeyEvent(
          cancel ? LogicalKeyboardKey.arrowDown : LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, isNot(same(editFocus)));
      final focusedContext = FocusManager.instance.primaryFocus!.context!;
      expect(
          cancel
              ? focusedContext.findAncestorWidgetOfExactType<TextButton>()
              : focusedContext.findAncestorWidgetOfExactType<FilledButton>(),
          isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(editor, findsNothing);
      expect(controller.text, cancel ? 'original' : 'first\nsecond');
      expect(changes, cancel ? 0 : 1);
      expect(entry.hasPrimaryFocus, isTrue);
    });
  }

  testWidgets('non TV multiline keeps native editing and no dialog',
      (tester) async {
    TvMode.setEnabledForTesting(false);
    final controller = TextEditingController(text: 'first\nsecond');
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TvTextEntry(
      child: TextField(controller: controller, focusNode: focus, maxLines: 8),
    ))));
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focus.hasPrimaryFocus, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
