import 'package:flutter/material.dart';
import 'dart:io';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/settings/settings_page.dart';
import 'package:kazumi/pages/settings/keyboard_settings.dart';
import 'package:kazumi/pages/settings/sync/local_library_backup_page.dart';
import 'package:kazumi/services/storage/local_library_backup.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('tv_settings_');
    PathProviderPlatform.instance = _Paths(temp.path);
    Hive.init(temp.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });
  for (final source in ['system', 'pane toolbar', 'settings toolbar']) {
    testWidgets('backup preview cancels before leaving via $source Back',
        (tester) async {
      TvMode.setEnabledForTesting(true);
      addTearDown(() => TvMode.setEnabledForTesting(false));
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = Directory('${temp.path}/preview-${source.hashCode}');
      final service = LocalLibraryBackupService(directory: () async => directory);
      await tester.runAsync(service.saveLocal);
      final storage = HiveLocalLibraryBackupStorage();
      final before = storage.read().fingerprint;
      final module = createModule(register: (c) {
        c.route('/settings',
            child: (_, state) => SettingsPage(location: state.uri.path),
            children: (sub) {
          sub.route('/sync', child: (context, _) => Center(
              child: TextButton(onPressed: () {
                context.pushNamed('/settings/sync/backup');
              }, child: const Text('Open backup'))));
          sub.route('/sync/backup', child: (_, __) =>
              LocalLibraryBackupPage(service: service));
        });
      });
      await tester.pumpWidget(ModularApp(
          module: module,
          initialRoute: '/settings/sync',
          child: Builder(builder: (context) => MaterialApp.router(
              routerConfig: ModularApp.routerConfigOf(context)))));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Open backup'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      final preview = find.textContaining('预览备份');
      expect(find.byType(LocalLibraryBackupPage), findsOneWidget);
      expect(await tester.runAsync(service.listLocal), hasLength(1));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(preview, 300,
          scrollable: find.descendant(
              of: find.byType(LocalLibraryBackupPage),
              matching: find.byType(Scrollable)).first);
      await tester.runAsync(() async {
        await tester.tap(preview);
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('恢复预览：'), findsOneWidget);
      if (source == 'system') {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(source == 'pane toolbar'
            ? find.byType(BackButton).last : find.byType(BackButton).first);
      }
      await tester.pumpAndSettle();
      expect(find.byType(LocalLibraryBackupPage), findsOneWidget);
      expect(find.textContaining('恢复预览：'), findsNothing);
      expect(find.text('已取消恢复，收藏与历史未改动。'), findsOneWidget);
      expect(storage.read().fingerprint, before);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LocalLibraryBackupPage), findsNothing);
      expect(find.text('Open backup'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('real remote guide tabs can return to the settings categories',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    addTearDown(() => TvMode.setEnabledForTesting(false));
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final module = createModule(register: (c) {
      c.route('/settings',
          child: (_, state) => SettingsPage(location: state.uri.path),
          children: (sub) {
            sub.route('/keyboard', child: (_, __) => const KeyboardSettingsPage());
          });
    });
    await tester.pumpWidget(ModularApp(
        module: module,
        initialRoute: '/settings/keyboard',
        child: Builder(builder: (context) => MaterialApp.router(
            routerConfig: ModularApp.routerConfigOf(context)))));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        'TV remote guide section');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        'TV custom shortcuts section');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        'TV settings category /settings/keyboard');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('TV settings leaves nested pane and selects another category',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    addTearDown(() => TvMode.setEnabledForTesting(false));
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget pane(String text) => Center(
        child:
            TextButton(autofocus: true, onPressed: () {}, child: Text(text)));
    final module = createModule(register: (c) {
      c.route('/settings',
          child: (_, state) => SettingsPage(location: state.uri.path),
          children: (sub) {
            sub.route('/', child: (_, __) => pane('播放内容'));
            sub.route('/player', child: (_, __) => pane('播放内容'));
            sub.route('/danmaku', child: (_, __) => pane('弹幕内容'));
          });
    });
    await tester.pumpWidget(ModularApp(
        module: module,
        initialRoute: '/settings',
        child: Builder(
            builder: (context) => MaterialApp.router(
                routerConfig: ModularApp.routerConfigOf(context)))));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        contains('/settings/player'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        contains('/settings/danmaku'));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('弹幕内容'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        isNot(contains('TV settings category')));
    expect(tester.takeException(), isNull);
  });
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}
