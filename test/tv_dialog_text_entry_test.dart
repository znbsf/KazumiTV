import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/tv_dialog_text_entry.dart';
import 'package:kazumi/bean/widget/tv_text_entry.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

void main() {
  tearDown(() => TvMode.setEnabledForTesting(false));
  for (final tv in [true, false]) {
    testWidgets('dialog controller lifetime and native parity tv=$tv',
        (tester) async {
      TvMode.setEnabledForTesting(tv);
      var changed = '';
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      autofocus: true,
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => AlertDialog(
                                  content: TvDialogTextEntry(
                                      title: 'skip',
                                      builder: (controller) => TextField(
                                          controller: controller,
                                          autofocus: true,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly
                                          ],
                                          onChanged: (value) =>
                                              changed = value)),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                        child: const Text('cancel'))
                                  ])),
                      child: const Text('open'))))));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, !tv);
      if (tv) {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(TextField), '1a2');
      if (tv) {
        expect(changed, '');
        tester.testTextInput.hide();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
      }
      expect(changed, '12');
      expect(
          tester
              .widget<TvTextEntry>(find.byType(TvTextEntry))
              .child
              .controller!
              .text,
          '12');
      tester.testTextInput.hide();
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
