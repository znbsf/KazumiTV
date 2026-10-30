import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/tv_text_prompt_dialog.dart';
import 'package:kazumi/bean/widget/tv_explicit_text_field.dart';
import 'package:kazumi/pages/video/episode_jump_dialog.dart';
import 'package:kazumi/services/phone_keyboard.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/pages/settings/sync/webdav_server_page.dart';
import 'package:kazumi/bean/widget/tv_text_form_entry.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _RealHttp extends HttpOverrides {}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Phone {
  _Phone(this.tester);
  final WidgetTester tester;
  final keyboard = PhoneKeyboard.instance;
  final client =
      HttpOverrides.runWithHttpOverrides(() => HttpClient(), _RealHttp());
  int serial = 0;
  Future<void> start() async {
    await tester
        .runAsync(() => keyboard.start(address: InternetAddress.loopbackIPv4));
    addTearDown(() async {
      client.close(force: true);
      await keyboard.disconnect();
    });
  }

  Map<String, Object?> payload(String action, [String text = '']) {
    final state = keyboard.session!.state;
    final target = state['target'] as Map;
    return {
      'requestId': '${++serial}',
      'generation': state['generation'],
      'targetId': target['id'],
      'revision': target['revision'],
      'action': action,
      'text': text
    };
  }

  Future<void> send(Map<String, Object?> data, [int status = 200]) async {
    await tester.runAsync(() async {
      final uri = keyboard.uri!;
      final req = await client.postUrl(uri.replace(path: '${uri.path}/input'));
      req.add(utf8.encode(jsonEncode(data)));
      final res = await req.close();
      await res.drain<void>();
      expect(res.statusCode, status);
    });
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() => TvMode.setEnabledForTesting(false));
  testWidgets(
      'explicit verification editor clears errors and suspends phone input when busy',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var busy = false, changes = 0, submits = 0;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
      update = setState;
      return TvExplicitTextField(
          label: '验证码',
          child: TextField(
              controller: controller,
              enabled: !busy,
              onChanged: (_) => changes++,
              onSubmitted: (_) => submits++));
    }))));
    final phone = _Phone(tester);
    await phone.start();
    await phone.send(phone.payload('input', 'FAKE123'));
    expect(changes, 1);
    await phone.send(phone.payload('confirm'));
    expect(submits, 0);
    final stale = phone.payload('input', 'late');
    update(() => busy = true);
    await tester.pumpAndSettle();
    expect(phone.keyboard.session!.state['target'], isNull);
    await phone.send(stale, 409);
    expect(controller.text, 'FAKE123');
    update(() => busy = false);
    await tester.pumpAndSettle();
    await phone.send(stale, 409);
    await phone.send(phone.payload('clear'));
    expect(controller.text, isEmpty);
    expect(changes, 2);
    await tester.pumpWidget(const SizedBox());
  });
  for (final title in ['弹幕检索', '发送弹幕']) {
    testWidgets('$title phone confirm keeps draft; only outer action submits',
        (tester) async {
      String? result = 'unchanged';
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        result = await showDialog<String>(
                            context: context,
                            builder: (_) => TvTextPromptDialog(
                                title: title,
                                initialText: '原始草稿',
                                hint: '内容',
                                submitLabel: '执行'));
                      },
                      child: const Text('打开'))))));
      final phone = _Phone(tester);
      await phone.start();
      Future<void> open() async {
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
      }

      await open();
      await phone.send(phone.payload('input', '中文\n草稿'));
      await phone.send(phone.payload('confirm'));
      expect(result, 'unchanged');
      expect(find.byType(TvTextPromptDialog), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '中文草稿');
      await phone.send(phone.payload('input', '继续修改'));
      final stale = phone.payload('input', '迟到请求');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(phone.keyboard.session!.state['target'], isNull);
      await open();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '原始草稿');
      await phone.send(stale, 409);
      await phone.send(phone.payload('input', '   '));
      await tester.tap(find.text('执行'));
      await tester.pumpAndSettle();
      expect(find.byType(TvTextPromptDialog), findsOneWidget);
      await phone.send(phone.payload('input', '最终内容'));
      await tester.tap(find.text('执行'));
      await tester.pumpAndSettle();
      expect(result, '最终内容');
      expect(phone.keyboard.session!.state['target'], isNull);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('episode phone digits, range validation and explicit locate',
      (tester) async {
    int? result = -1;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await showEpisodeJumpDialog(context, count: 20);
                    },
                    child: const Text('打开'))))));
    final phone = _Phone(tester);
    await phone.start();
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await phone.send(phone.payload('input', '字99母'));
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '99');
    await phone.send(phone.payload('confirm'));
    expect(result, -1);
    await tester.tap(find.text('定位'));
    await tester.pumpAndSettle();
    expect(find.text('请输入 1–20 的原始集序号'), findsOneWidget);
    await phone.send(phone.payload('input', '7'));
    await tester.tap(find.text('定位'));
    await tester.pumpAndSettle();
    expect(result, 6);
    expect(phone.keyboard.session!.state['target'], isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'WebDAV actual password field is write-only even when visible; confirm never saves',
      (tester) async {
    final originalPaths = PathProviderPlatform.instance;
    final directory = await tester
        .runAsync(() => Directory.systemTemp.createTemp('kazumi_issue34_'));
    PathProviderPlatform.instance = _Paths(directory!.path);
    await tester.runAsync(() async {
      Hive.init(directory.path);
      await GStorage.init();
      await GStorage.putSetting(
          SettingsKeys.webDavPassword, 'fake-stored-password');
    });
    addTearDown(() async {
      await Hive.close();
      PathProviderPlatform.instance = originalPaths;
      expect(
          directory.absolute.path
              .startsWith(Directory.systemTemp.absolute.path),
          isTrue);
      await directory.delete(recursive: true);
    });
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: WebDavServerPage()));
    await tester.pumpAndSettle();
    final phone = _Phone(tester);
    await phone.start();
    phone.keyboard.setReadTextAllowed(true);
    final password = find.byWidgetPredicate(
        (w) => w is TvTextFormEntry && w.phoneKeyboardWriteOnly);
    for (final visible in [false, true]) {
      if (visible) {
        await tester.tap(find.byTooltip('显示密码'));
        await tester.pumpAndSettle();
      }
      await tester.tap(
          find.descendant(of: password, matching: find.byType(InputDecorator)));
      await tester.pumpAndSettle();
      final target = phone.keyboard.session!.state['target'] as Map;
      expect(target['writeOnly'], isTrue);
      expect(target.containsKey('text'), isFalse);
      expect(jsonEncode(phone.keyboard.session!.state),
          isNot(contains('fake-stored-password')));
      await phone.send(phone.payload('input', 'fake-new-password'));
      if (!visible) {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      } else {
        await phone.send(phone.payload('confirm'));
      }
      expect(GStorage.getSetting(SettingsKeys.webDavPassword),
          'fake-stored-password');
      expect(find.text('正在测试连接…'), findsNothing);
      expect(find.text('请输入完整的 http:// 或 https:// 地址'), findsNothing);
      expect(phone.keyboard.session!.state['target'], isNull);
    }
    expect(tester.widget<TvTextFormEntry>(password).controller.text,
        'fake-new-password');
    await tester.tap(
        find.descendant(of: password, matching: find.byType(InputDecorator)));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('tv-text-editor')), 'fake-tv-draft');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(tester.widget<TvTextFormEntry>(password).controller.text,
        'fake-tv-draft');
    expect(find.text('请输入完整的 http:// 或 https:// 地址'), findsNothing);
    expect(GStorage.getSetting(SettingsKeys.webDavPassword),
        'fake-stored-password');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
