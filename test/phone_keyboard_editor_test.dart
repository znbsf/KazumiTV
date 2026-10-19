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
      'phone handshake closes QR dialog and retains session and editor target',
      (tester) async {
    final controller = TextEditingController(text: 'original');
    final focus = FocusNode();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TvTextEntry(
                title: 'Search',
                child: TextField(controller: controller, focusNode: focus)))));
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    final keyboard = PhoneKeyboard.instance;
    await tester
        .runAsync(() => keyboard.start(address: InternetAddress.loopbackIPv4));
    final target = keyboard.session!.state['target'];
    final context = tester.element(find.byKey(const Key('tv-text-editor')));
    showDialog<void>(
        context: context, builder: (_) => const PhoneKeyboardDialog());
    await tester.pumpAndSettle();
    expect(find.byType(PhoneKeyboardDialog), findsOneWidget);
    final client =
        HttpOverrides.runWithHttpOverrides(() => HttpClient(), _RealHttp());
    await tester.runAsync(() async {
      final uri = keyboard.uri!;
      final response =
          await (await client.getUrl(uri.replace(path: '${uri.path}/state')))
              .close();
      await response.drain<void>();
    });
    await tester.pumpAndSettle();
    expect(find.byType(PhoneKeyboardDialog), findsNothing);
    expect(keyboard.session!.isClosed, isFalse);
    expect(keyboard.session!.state['target'], target);
    expect(find.byKey(const Key('tv-text-editor')), findsOneWidget);
    client.close(force: true);
    await tester.runAsync(keyboard.disconnect);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    focus.dispose();
  });
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
    expect(find.text('断开全部（1）'), findsOneWidget);
    expect(find.text('已连接 1 个遥控端'), findsOneWidget);
    expect((keyboard.session!.state['remote'] as Map)['keys'], isEmpty);
    expect(
        await send({
          'requestId': 'remote-consent',
          'action': 'remote',
          'key': 'ok',
          'remoteRevision': -1,
          'remoteSequence': 1
        }),
        409);
    expect(keyboard.readTextAllowed, isFalse);
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(keyboard.readTextAllowed, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(keyboard.session!.state['target'], isNotNull);
    expect((keyboard.session!.state['target'] as Map)['text'], 'second');
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
    expect(keyboard.readTextAllowed, isFalse);
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
        'write-only Token replacement and cancellation obscure=$obscure',
        (tester) async {
      final controller = TextEditingController(text: 'previous-secret-token');
      final focus = FocusNode();
      var submits = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: TvTextEntry(
                  phoneKeyboardWriteOnly: true,
                  child: TextField(
                      controller: controller,
                      focusNode: focus,
                      obscureText: obscure,
                      decoration:
                          const InputDecoration(labelText: 'Access Token'),
                      onSubmitted: (_) => submits++)))));
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(PhoneKeyboardButton), findsOneWidget);
      final keyboard = PhoneKeyboard.instance;
      await tester.runAsync(() async {
        keyboard.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await keyboard.start(address: InternetAddress.loopbackIPv4);
      });
      expect(keyboard.uri, isNotNull);
      keyboard.setReadTextAllowed(true);
      final client =
          HttpOverrides.runWithHttpOverrides(() => HttpClient(), _RealHttp());
      var serial = 0;
      Future<int?> send(String action, [String text = '']) =>
          tester.runAsync(() async {
            final state = keyboard.session!.state;
            expect(jsonEncode(state), isNot(contains('previous-secret-token')));
            expect(state['readTextAllowed'], false);
            final target = state['target'] as Map;
            expect(target['writeOnly'], true);
            final uri = keyboard.uri!;
            final req =
                await client.postUrl(uri.replace(path: '${uri.path}/input'));
            req.add(utf8.encode(jsonEncode({
              'requestId': 'credential-${++serial}',
              'generation': state['generation'],
              'targetId': target['id'],
              'revision': target['revision'],
              'action': action,
              'text': text,
            })));
            final response = await req.close();
            final body = await utf8.decoder.bind(response).join();
            expect(body, isNot(contains('previous-secret-token')));
            expect(body, isNot(contains('replacement-token')));
            return response.statusCode;
          });
      expect(await send('input', 'discard-this-token'), 200);
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(controller.text, 'previous-secret-token');
      expect(keyboard.session!.state['target'], isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(await send('input', 'replacement-token'), 200);
      await tester.pump();
      expect(controller.text, 'previous-secret-token');
      expect(await send('confirm'), 200);
      await tester.pumpAndSettle();
      expect(controller.text, 'replacement-token');
      expect(submits, 0,
          reason: 'Saving/verification still needs TV confirmation');
      expect(keyboard.session!.state['target'], isNull);
      client.close(force: true);
      await tester.runAsync(keyboard.disconnect);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      focus.dispose();
    });

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
