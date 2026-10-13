import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/bean/dialog/dialog.dart';
import 'package:kazumi/bean/widget/tv_text_entry.dart';
import 'package:kazumi/pages/plugin_editor/rule_dialogs.dart';
import 'package:kazumi/pages/settings/player_settings.dart';
import 'package:kazumi/pages/settings/settings_page.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/storage/storage.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

Future<void> _editDraft(WidgetTester tester, String value) async {
  final entry = find.byType(TvTextEntry);
  expect(entry, findsOneWidget);
  expect(tester.testTextInput.isVisible, isFalse);
  Focus.of(tester.element(
          find.descendant(of: entry, matching: find.byType(InputDecorator))))
      .requestFocus();
  await tester.pump();
  await _key(tester, LogicalKeyboardKey.enter);
  final editor = find.byKey(const Key('tv-text-editor'));
  await tester.enterText(editor, value);
  tester.testTextInput.hide();
  await _key(tester, LogicalKeyboardKey.arrowUp);
  expect(
      FocusManager.instance.primaryFocus!.context!
          .findAncestorWidgetOfExactType<FilledButton>(),
      isNotNull);
  await _key(tester, LogicalKeyboardKey.enter);
  expect(editor, findsNothing);
  expect(tester.widget<TvTextEntry>(entry).child.controller!.text, value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late PathProviderPlatform oldPaths;
  setUpAll(() async {
    oldPaths = PathProviderPlatform.instance;
    dir = await Directory.systemTemp.createTemp('raw_tv_input_');
    PathProviderPlatform.instance = _Paths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = oldPaths;
    await dir.delete(recursive: true);
  });
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() => TvMode.setEnabledForTesting(false));

  testWidgets(
      'real rule import editor commits draft only; outer cancel never writes',
      (tester) async {
    var writes = 0;
    final controller = PluginsController(pluginJsonWriter: (_) async {
      writes++;
    });
    await tester.pumpWidget(MaterialApp(
        navigatorObservers: [KazumiDialog.observer],
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    autofocus: true,
                    onPressed: () => showRuleImportDialog(context, controller),
                    child: const Text('open'))))));
    await tester.pumpAndSettle();
    await _key(tester, LogicalKeyboardKey.enter);
    await _editDraft(tester, 'invalid\nrule');
    expect(writes, 0);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(
        FocusManager.instance.primaryFocus!.context!
            .findAncestorWidgetOfExactType<TextButton>(),
        isNotNull);
    await _key(tester, LogicalKeyboardKey.enter);
    expect(find.byType(AlertDialog), findsNothing);
    expect(writes, 0);
  });

  testWidgets(
      'real settings skip entry preserves draft without writing before outer confirm',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final before = GStorage.getSetting(SettingsKeys.buttonSkipTime);
    await tester.pumpWidget(ModularApp(
        navigatorObservers: [KazumiDialog.observer],
        module: createModule(register: (c) {
          c.route('/settings',
              child: (_, state) => SettingsPage(location: state.uri.path),
              children: (sub) {
                sub.route('/player',
                    child: (_, __) => const PlayerSettingsPage());
              });
        }),
        initialRoute: '/settings/player',
        child: Builder(
            builder: (context) => MaterialApp.router(
                routerConfig: ModularApp.routerConfigOf(context)))));
    await tester.pumpAndSettle();
    final row = find.text('跳过时长');
    await tester.scrollUntilVisible(row, 300,
        scrollable: find
            .descendant(
                of: find.byType(PlayerSettingsPage),
                matching: find.byType(Scrollable))
            .first);
    Focus.of(tester.element(row)).requestFocus();
    await tester.pump();
    await _key(tester, LogicalKeyboardKey.enter);
    await _editDraft(tester, '25');
    expect(GStorage.getSetting(SettingsKeys.buttonSkipTime), before);
    // Reopening starts from the confirmed draft, not an empty controller.
    await _key(tester, LogicalKeyboardKey.enter);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('tv-text-editor')))
            .controller!
            .text,
        '25');
    tester.testTextInput.hide();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.enter);
    expect(find.byType(AlertDialog), findsNothing);
    expect(GStorage.getSetting(SettingsKeys.buttonSkipTime), before);
  });
}
