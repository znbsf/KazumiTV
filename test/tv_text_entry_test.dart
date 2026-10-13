import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/tv_text_entry.dart';
import 'package:kazumi/pages/plugin_editor/editor_form_widgets.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

void main() {
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() => TvMode.setEnabledForTesting(false));
  testWidgets('rule field navigation does not start editing before OK',
      (tester) async {
    final controller = TextEditingController();
    final below = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(below.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      const TextButton(onPressed: null, child: Text('above')),
      EditorTextField(controller: controller, label: 'Rule'),
      TextButton(
          focusNode: below, onPressed: () {}, child: const Text('below')),
    ]))));
    below.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse,
        reason: 'D-pad navigation must not open the IME');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets(
      'OK repeat opens once; Back cancels and returns entry; reopen commits once',
      (tester) async {
    final controller = TextEditingController(text: 'initial');
    final entry = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(entry.dispose);
    var changes = 0;
    var submits = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TvTextEntry(
                child: TextField(
      controller: controller,
      focusNode: entry,
      onChanged: (_) => changes++,
      onSubmitted: (_) => submits++,
    )))));
    entry.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('tv-text-editor')), 'cancelled');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(controller.text, 'initial');
    expect(entry.hasFocus, isTrue);
    expect(changes, 0);
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tv-text-editor')), '');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(controller.text, '');
    expect(changes, 1);
    expect(submits, 1);
    expect(entry.hasFocus, isTrue);
  });

  testWidgets('navigation down repeat/up, boundary and suffix do not edit',
      (tester) async {
    final controller = TextEditingController(text: 'value');
    final entry = FocusNode();
    final below = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(entry.dispose);
    addTearDown(below.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      TvTextEntry(
          child: TextField(
              controller: controller,
              focusNode: entry,
              decoration: InputDecoration(
                  suffixIcon: IconButton(
                      onPressed: controller.clear,
                      icon: const Icon(Icons.clear))))),
      TextButton(
          focusNode: below, onPressed: () {}, child: const Text('below')),
    ]))));
    entry.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(below.hasFocus, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();
    expect(controller.text, '');
  });

  testWidgets(
      'disabled excludes entry; TV touch opens editor; mobile stays native',
      (tester) async {
    final controller = TextEditingController(text: 'value');
    addTearDown(controller.dispose);
    Widget app(bool enabled) => MaterialApp(
        home: Scaffold(
            body: TvTextEntry(
                child: TextField(controller: controller, enabled: enabled))));
    await tester.pumpWidget(app(false));
    await tester.tap(find.text('value'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(app(true));
    await tester.tap(find.text('value'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    TvMode.setEnabledForTesting(false);
    await tester.pumpWidget(app(true));
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets(
      'multiline draft and formatters survive; cancel does not change source',
      (tester) async {
    final controller = TextEditingController(text: '12');
    final entry = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(entry.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TvTextEntry(
                child: TextField(
      controller: controller,
      focusNode: entry,
      maxLines: 4,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9\\n]'))],
    )))));
    entry.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tv-text-editor')), '34a\n56');
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('tv-text-editor')))
            .controller!
            .text,
        '34\n56');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(controller.text, '34\n56');
  });
  testWidgets('Enter repeat does not resubmit or pop parent route',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final controller = TextEditingController();
    final entry = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(entry.dispose);
    var submits = 0;
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator, home: const Scaffold(body: Text('home'))));
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
                body: Column(children: [
              const Text('detail'),
              TvTextEntry(
                  child: TextField(
                      controller: controller,
                      focusNode: entry,
                      onSubmitted: (_) => submits++)),
            ]))));
    await tester.pumpAndSettle();
    entry.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(submits, 0);
    final editor =
        tester.widget<TextField>(find.byKey(const Key('tv-text-editor')));
    editor.onSubmitted!('');
    editor.onSubmitted!('');
    await tester.pumpAndSettle();
    expect(submits, 1);
    expect(find.text('detail'), findsOneWidget);
    expect(entry.hasFocus, true);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });
}
