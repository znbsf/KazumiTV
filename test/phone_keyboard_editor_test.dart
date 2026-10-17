import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/tv_text_entry.dart';
import 'package:kazumi/bean/widget/tv_search_entry.dart';
import 'package:kazumi/bean/widget/phone_keyboard_control.dart';
import 'package:kazumi/services/phone_keyboard.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() => TvMode.setEnabledForTesting(false));

  testWidgets(
      'only explicit editors accept multiple edits; confirm never submits an action',
      (tester) async {
    final a = TextEditingController(text: 'https://private/?token=secret');
    final b = TextEditingController(text: 'second');
    final search = TextEditingController();
    final fa = FocusNode(), fb = FocusNode();
    var submits = 0, changes = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      TvTextEntry(
          title: 'Rule URL',
          child: TextField(
              controller: a,
              focusNode: fa,
              onChanged: (_) => changes++,
              onSubmitted: (_) => submits++)),
      TvTextEntry(
          title: 'Search', child: TextField(controller: b, focusNode: fb)),
      TvSearchEntry(controller: search, onSubmitted: (_) => submits++),
    ]))));
    final keyboard = PhoneKeyboard.instance;
    await tester
        .runAsync(() => keyboard.start(address: InternetAddress.loopbackIPv4));
    final uri = keyboard.uri!;
    final client =
        HttpOverrides.runWithHttpOverrides(() => HttpClient(), _RealHttp());
    var id = 0;
    Map<String, Object?> payload(String action, [String text = '']) {
      final state = keyboard.session!.state;
      final target = state['target'] as Map<String, Object?>?;
      return {
        'requestId': '${++id}',
        'generation': state['generation'],
        'targetId': target?['id'],
        'revision': target?['revision'],
        'action': action,
        'text': text
      };
    }

    Future<int?> send(Map<String, Object?> data) => tester.runAsync(() async {
          final req =
              await client.postUrl(uri.replace(path: '${uri.path}/input'));
          req.add(utf8.encode(jsonEncode(data)));
          final res = await req.close();
          await res.drain<void>();
          return res.statusCode;
        });
    fa.requestFocus();
    await tester.pump();
    expect(keyboard.session!.state['target'], isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(jsonEncode(keyboard.session!.state), isNot(contains('secret')));
    final stale = payload('input', 'must not cross fields');
    expect(await send(payload('input', '中文')), 200);
    await tester.pump();
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('tv-text-editor')))
            .controller!
            .text,
        '中文');
    final beforeLocalEdit = payload('input', 'stale phone edit');
    await tester.enterText(
        find.byKey(const Key('tv-text-editor')), 'local edit');
    expect(await send(beforeLocalEdit), 409);
    expect(await send(payload('clear')), 200);
    await tester.pump();
    expect(await send(payload('input', 'new\n URL')), 200);
    await tester.pump();
    expect(await send(payload('confirm')), 200);
    await tester.pumpAndSettle();
    expect(a.text, 'new URL');
    expect(changes, 1);
    expect(submits, 0);
    expect(fa.hasFocus, isTrue);
    expect(keyboard.session!.state['target'], isNull);
    fb.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(await send(stale), 409);
    expect(keyboard.uri, uri);
    await tester.tap(find.byType(PhoneKeyboardButton));
    await tester.pumpAndSettle();
    expect(keyboard.session!.state['target'], isNull,
        reason: 'Covered editor is not an active target');
    expect(find.text(uri.toString()), findsOneWidget);
    expect(find.text('断开连接'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(keyboard.session!.state['target'], isNotNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(keyboard.session!.state['target'], isNull);
    expect(fb.hasFocus, isTrue);
    await tester.tap(find.byKey(const Key('tv-search-entry')));
    await tester.pumpAndSettle();
    expect(await send(payload('input', 'search text')), 200);
    await tester.pump();
    expect(await send(payload('confirm')), 200);
    await tester.pumpAndSettle();
    expect(search.text, 'search text');
    expect(submits, 0);
    await tester.runAsync(() async {
      keyboard.didChangeAppLifecycleState(AppLifecycleState.paused);
      await keyboard.disconnect();
    });
    expect(keyboard.uri, isNull);
    client.close(force: true);
    await tester.pumpWidget(const SizedBox());
    a.dispose();
    b.dispose();
    search.dispose();
    fa.dispose();
    fb.dispose();
  });

  for (final obscure in [false, true]) {
    testWidgets(
        'sensitive field excludes phone input even when visible=$obscure',
        (tester) async {
      final controller = TextEditingController(text: 'secret');
      final focus = FocusNode();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: TvTextEntry(
                  allowPhoneKeyboard: false,
                  child: TextField(
                      controller: controller,
                      focusNode: focus,
                      obscureText: obscure)))));
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(PhoneKeyboardButton), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      focus.dispose();
    });
  }
}
