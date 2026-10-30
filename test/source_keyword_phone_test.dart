import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/info/source_keyword_dialog.dart';
import 'package:kazumi/bean/widget/tv_text_entry.dart';
import 'package:kazumi/services/phone_keyboard.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  tearDown(() => TvMode.setEnabledForTesting(false));
  testWidgets(
      'phone edits source keyword draft without searching; cancel discards',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    final submitted = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (context) => SourceKeywordDialog(
                            initialKeyword: '原检索词',
                            sourceName: '测试源',
                            onSubmit: (value) {
                              submitted.add(value);
                              Navigator.pop(context);
                            },
                            onCancel: () => Navigator.pop(context))),
                    child: const Text('打开'))))));
    final keyboard = PhoneKeyboard.instance;
    await tester
        .runAsync(() => keyboard.start(address: InternetAddress.loopbackIPv4));
    final client =
        HttpOverrides.runWithHttpOverrides(() => HttpClient(), _RealHttp());
    addTearDown(() async {
      client.close(force: true);
      await keyboard.disconnect();
    });
    var serial = 0;
    Future<void> send(String action,
        [String text = '',
        Map<String, Object?>? snapshot,
        int status = 200]) async {
      final state = snapshot ?? keyboard.session!.state;
      final target = state['target'] as Map;
      await tester.runAsync(() async {
        final uri = keyboard.uri!;
        final request =
            await client.postUrl(uri.replace(path: '${uri.path}/input'));
        request.add(utf8.encode(jsonEncode({
          'requestId': '${++serial}',
          'generation': state['generation'],
          'targetId': target['id'],
          'revision': target['revision'],
          'action': action,
          'text': text
        })));
        final response = await request.close();
        await response.drain<void>();
        expect(response.statusCode, status);
      });
      await tester.pumpAndSettle();
    }

    Future<void> openEditor() async {
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(keyboard.session!.state['target'], isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(keyboard.session!.state['target'], isNotNull);
    }

    await openEditor();
    await send('input', ' 新检索词 ');
    final oldTarget = keyboard.session!.state;
    await send('confirm');
    expect(submitted, isEmpty);
    expect(find.text(' 新检索词 '), findsOneWidget);
    expect(keyboard.session!.state['target'], isNull);
    expect(
        FocusManager.instance.primaryFocus!.context!
            .findAncestorWidgetOfExactType<TvTextEntry>(),
        isNotNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await openEditor();
    await send('input', '迟到的旧输入', oldTarget, 409);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('tv-text-editor')))
            .controller!
            .text,
        '原检索词');
    await send('input', '   ');
    await send('confirm');
    await tester.tap(find.text('检索'));
    await tester.pumpAndSettle();
    expect(submitted, isEmpty);
    expect(find.byType(SourceKeywordDialog), findsOneWidget);
    // Re-open the editor after an empty draft was rejected.
    await tester.tap(find.text('   '));
    await tester.pumpAndSettle();
    await send('input', '  约会大作战  ');
    await send('confirm');
    await tester.tap(find.text('检索'));
    await tester.pumpAndSettle();
    expect(submitted, ['约会大作战']);
    expect(find.byType(SourceKeywordDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('TV editor confirmation only saves draft; Back discards edits',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    final submitted = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SourceKeywordDialog(
                initialKeyword: '原词',
                sourceName: '测试源',
                onSubmit: submitted.add,
                onCancel: () {}))));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tv-text-editor')), '新的草稿');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(submitted, isEmpty);
    expect(find.text('新的草稿'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tv-text-editor')), '取消的草稿');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('新的草稿'), findsOneWidget);
    expect(find.text('取消的草稿'), findsNothing);
    expect(submitted, isEmpty);
    await tester.tap(find.text('检索'));
    await tester.pumpAndSettle();
    expect(submitted, ['新的草稿']);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-TV field retains direct editing and keyboard submission',
      (tester) async {
    TvMode.setEnabledForTesting(false);
    final submitted = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: SourceKeywordDialog(
            initialKeyword: '原词',
            sourceName: '测试源',
            onSubmit: submitted.add,
            onCancel: () {})));
    await tester.enterText(find.byType(TextField), '  新词  ');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(submitted, ['新词']);
    expect(find.byKey(const Key('tv-text-editor')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
