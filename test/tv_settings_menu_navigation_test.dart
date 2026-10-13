import 'dart:io';
import 'package:kazumi/pages/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/pages/settings/interface_settings.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/settings/theme_provider.dart';
import 'package:kazumi/pages/settings/theme_settings_page.dart';
import 'package:kazumi/pages/settings/player_settings.dart';
import 'package:kazumi/pages/settings/danmaku/danmaku_settings.dart';

class Paths extends PathProviderPlatform {
  Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('settings_menu_');
    PathProviderPlatform.instance = Paths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  for (final item in <(String, Widget)>[
    ('启动界面设置', const InterfaceSettingsPage()),
    ('深色模式', const ThemeSettingsPage()),
    ('日志等级', const PlayerSettingsPage()),
    ('默认视频比例', const PlayerSettingsPage()),
    ('简繁转换', const DanmakuSettingsPage()),
  ]) {
    testWidgets(
        'actual ${item.$1} menu owns arrows and system Back then restores row',
        (tester) async {
      TvMode.setEnabledForTesting(true);
      addTearDown(() => TvMode.setEnabledForTesting(false));
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final nav = GlobalKey<NavigatorState>();
      final provider = ThemeProvider()..setTheme(ThemeData(), ThemeData.dark());
      await tester.pumpWidget(ModularApp(
          navigatorKey: nav,
          module: createModule(register: (c) {
            c.route('/settings',
                child: (_, state) => SettingsPage(location: state.uri.path),
                children: (sub) {
                  sub.route('/theme', child: (_, __) => item.$2);
                });
          }),
          initialRoute: '/settings/theme',
          provide: (scope) =>
              scope.addChangeNotifier<ThemeProvider>(() => provider),
          child: Builder(
              builder: (context) => MaterialApp.router(
                  routerConfig: ModularApp.routerConfigOf(context)))));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(item.$1), 300,
          scrollable: find
              .descendant(
                  of: find.byType(item.$2.runtimeType),
                  matching: find.byType(Scrollable))
              .first);
      await tester.pumpAndSettle();
      final row = Focus.of(tester.element(find.text(item.$1)));
      row.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      bool inMenu() =>
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<MenuItemButton>() !=
          null;
      expect(inMenu(), isTrue,
          reason: 'programmatic open must focus an actual menu item');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(inMenu(), isTrue,
          reason: 'Down must not reach the setting below the menu');
      await nav.currentState!.maybePop();
      await tester.pumpAndSettle();
      expect(find.byType(item.$2.runtimeType), findsOneWidget);
      expect(find.byType(MenuItemButton), findsNothing);
      expect(row.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(inMenu(), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
      expect(row.hasPrimaryFocus, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
