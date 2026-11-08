import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/dialog/dialog.dart';
import 'package:kazumi/bean/dialog/tv_dialog_initial_focus.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/pages/plugin_editor/rule_dialogs.dart';
import 'package:kazumi/pages/settings/theme_settings_page.dart';

void main() {
  tearDown(() => TvMode.setEnabledForTesting(false));
  for (final tv in [true, false]) {
    for (final autofocus in [false, true]) {
      testWidgets('D02 initial focus tv=$tv autofocus=$autofocus',
          (tester) async {
        TvMode.setEnabledForTesting(tv);
        late BuildContext context;
        await tester.pumpWidget(MaterialApp(home: Builder(builder: (ctx) {
          context = ctx;
          return const Scaffold();
        })));
        final cancel = FocusNode();
        final confirm = FocusNode();
        addTearDown(cancel.dispose);
        addTearDown(confirm.dispose);
        final revision = ValueNotifier(0);
        addTearDown(revision.dispose);
        KazumiDialog.show<void>(
            context: context,
            builder: (_) => ValueListenableBuilder<int>(
                valueListenable: revision,
                builder: (_, value, __) => AlertDialog(
                      title: Text('$value'),
                      actions: [
                        TextButton(
                            focusNode: cancel,
                            onPressed: () {},
                            child: const Text('取消')),
                        FilledButton(
                            focusNode: confirm,
                            autofocus: autofocus,
                            onPressed: () {},
                            child: const Text('确认')),
                      ],
                    )));
        await tester.pumpAndSettle();
        expect(find.byType(TvDialogInitialFocus),
            tv ? findsOneWidget : findsNothing);
        expect(confirm.hasPrimaryFocus, autofocus);
        expect(cancel.hasPrimaryFocus, tv && !autofocus);
        // A rebuild and later frame must not pull focus back to the fallback.
        confirm.requestFocus();
        await tester.pumpAndSettle();
        revision.value++;
        await tester.pumpAndSettle();
        expect(confirm.hasPrimaryFocus, isTrue);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }
  }

  testWidgets('D02 real rule deletion initially focuses retain',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (ctx) {
      context = ctx;
      return const Scaffold();
    })));
    final result = confirmRuleDeletion(context, {'test'});
    await tester.pumpAndSettle();
    expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<TextButton>(),
        same(tester.widget<TextButton>(find.widgetWithText(TextButton, '保留'))));
    await tester.tap(find.text('保留'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('D02 raw palette fallback tolerates unmatched saved color',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (ctx) {
      context = ctx;
      return const Scaffold();
    })));
    showDialog<int>(
        context: context,
        builder: (_) => const TvDialogInitialFocus(
            child: ThemePaletteDialog(selectedColor: 'unmatched')));
    await tester.pumpAndSettle();
    expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<OutlinedButton>(),
        same(tester.widget<OutlinedButton>(
            find.byKey(const ValueKey('theme-palette-0')))));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
      'D02 empty first frame tolerates later async controls without stealing',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (ctx) {
      context = ctx;
      return const Scaffold();
    })));
    final ready = ValueNotifier(false);
    final node = FocusNode();
    addTearDown(ready.dispose);
    addTearDown(node.dispose);
    KazumiDialog.show<void>(
        context: context,
        builder: (_) => ValueListenableBuilder<bool>(
              valueListenable: ready,
              builder: (_, value, __) => AlertDialog(
                  actions: value
                      ? [
                          TextButton(
                              focusNode: node,
                              onPressed: () {},
                              child: const Text('later')),
                        ]
                      : null),
            ));
    await tester.pumpAndSettle();
    ready.value = true;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(node.hasPrimaryFocus, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
