import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/tv_text_form_entry.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

void main() {
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() => TvMode.setEnabledForTesting(false));
  testWidgets(
      'form navigation, cancel, commit, validate, save and reset retain semantics',
      (tester) async {
    final controller = TextEditingController(text: 'initial');
    final focus = FocusNode();
    final below = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    addTearDown(below.dispose);
    final form = GlobalKey<FormState>();
    String? saved;
    var changes = 0, submits = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Form(
                key: form,
                child: Column(children: [
                  TvTextFormEntry(
                      controller: controller,
                      focusNode: focus,
                      validator: (v) => v == 'valid' ? null : 'invalid',
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      onSaved: (v) => saved = v,
                      onChanged: (_) => changes++,
                      onFieldSubmitted: (_) => submits++),
                  TextButton(
                      focusNode: below,
                      onPressed: () {},
                      child: const Text('below')),
                ])))));
    focus.requestFocus();
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(below.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(focus.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('tv-text-editor')), 'cancelled');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(controller.text, 'initial');
    expect(changes, 0);
    expect(submits, 0);
    expect(focus.hasPrimaryFocus, isTrue);
    expect(form.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('invalid'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tv-text-editor')), 'valid');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.text, 'valid');
    expect(changes, 1);
    expect(submits, 1);
    expect(form.currentState!.validate(), isTrue);
    form.currentState!.save();
    expect(saved, 'valid');
    expect(find.text('invalid'), findsNothing);
    form.currentState!.reset();
    await tester.pump();
    expect(controller.text, 'initial');
    expect(find.text('invalid'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'controller replacement and external changes feed current form value',
      (tester) async {
    final a = TextEditingController(text: 'a'),
        b = TextEditingController(text: 'b');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    final form = GlobalKey<FormState>();
    String? saved;
    Widget app(TextEditingController c) => MaterialApp(
        home: Scaffold(
            body: Form(
                key: form,
                child: TvTextFormEntry(
                    controller: c, onSaved: (v) => saved = v))));
    await tester.pumpWidget(app(a));
    a.text = 'external';
    await tester.pump();
    form.currentState!.save();
    expect(saved, 'external');
    await tester.pumpWidget(app(b));
    a.text = 'stale';
    await tester.pump();
    form.currentState!.save();
    expect(saved, 'b');
    b.text = 'current';
    await tester.pump();
    form.currentState!.save();
    expect(saved, 'current');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'password preview stays obscured, suffix reachable, disabled cannot edit',
      (tester) async {
    final c = TextEditingController(text: 'secret');
    addTearDown(c.dispose);
    var suffix = 0;
    Widget app(bool enabled) => MaterialApp(
        home: Scaffold(
            body: TvTextFormEntry(
                controller: c,
                enabled: enabled,
                obscureText: true,
                decoration: InputDecoration(
                    labelText: 'password',
                    suffixIcon: IconButton(
                        onPressed: () => suffix++,
                        icon: const Icon(Icons.visibility))))));
    await tester.pumpWidget(app(true));
    expect(find.text('secret'), findsNothing);
    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pump();
    expect(suffix, 1);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.byType(InputDecorator));
    await tester.pumpAndSettle();
    final field =
        tester.widget<TextField>(find.byKey(const Key('tv-text-editor')));
    expect(field.obscureText, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(false));
    await tester.tap(find.byType(InputDecorator));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('room formatters and autovalidation apply on committed draft',
      (tester) async {
    final c = TextEditingController();
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Form(
                child: TvTextFormEntry(
                    controller: c,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: (v) => v!.length == 6 ? null : 'six digits')))));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tv-text-editor')), 'ab12');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.text, '12');
    expect(find.text('six digits'), findsOneWidget);
  });
  testWidgets('mobile retains native editable TextFormField and validator',
      (tester) async {
    TvMode.setEnabledForTesting(false);
    final c = TextEditingController();
    addTearDown(c.dispose);
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Form(
                key: form,
                child: TvTextFormEntry(
                    controller: c,
                    validator: (v) => v!.isEmpty ? 'required' : null)))));
    expect(find.byType(TextFormField), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'mobile');
    expect(c.text, 'mobile');
    expect(form.currentState!.validate(), isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets(
      'disabled field retains validator and form value through re-enable',
      (tester) async {
    final c = TextEditingController(text: 'bad');
    addTearDown(c.dispose);
    final form = GlobalKey<FormState>();
    String? saved;
    Widget app(bool enabled) => MaterialApp(
        home: Scaffold(
            body: Form(
                key: form,
                child: TvTextFormEntry(
                    controller: c,
                    enabled: enabled,
                    validator: (v) => v == 'good' ? null : 'invalid',
                    onSaved: (v) => saved = v))));
    await tester.pumpWidget(app(false));
    expect(form.currentState!.validate(), isFalse);
    form.currentState!.save();
    expect(saved, 'bad');
    await tester.pumpWidget(app(true));
    expect(form.currentState!.validate(), isFalse);
    c.text = 'good';
    await tester.pump();
    expect(form.currentState!.validate(), isTrue);
    form.currentState!.save();
    expect(saved, 'good');
  });
}
