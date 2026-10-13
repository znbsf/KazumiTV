import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/bean/settings/theme_provider.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/widget/tv_visuals.dart';
import 'package:kazumi/pages/settings/theme_settings_page.dart';
import 'package:kazumi/services/storage/storage.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late ThemeProvider provider;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('theme_settings_');
    PathProviderPlatform.instance = _Paths(temp.path);
    Hive.init(temp.path);
    await GStorage.init();
    provider = ThemeProvider()
      ..setTheme(
          ThemeData(colorSchemeSeed: Colors.green),
          ThemeData(
              colorSchemeSeed: Colors.green, brightness: Brightness.dark));
    bootstrapModule(
        createModule(register: (c) => c.addInstance<ThemeProvider>(provider)));
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });
  testWidgets('real settings remote palette persists and cancel preserves it',
      (tester) async {
    await tester.runAsync(() async {
      await GStorage.putSetting(SettingsKeys.themeColor, 'default');
      await GStorage.putSetting(SettingsKeys.useDynamicColor, false);
      var revision = 0;
      final module = createModule(register: (_) {});
      Widget page() => ModularApp(
          module: module,
          provide: (scope) =>
              scope.addChangeNotifier<ThemeProvider>(() => provider),
          child: ListenableBuilder(
              listenable: provider,
              builder: (_, __) => MaterialApp(
                  theme: TvVisuals.theme(provider.light),
                  home: SettingsPaneScope(
                      embedded: true,
                      showBackButton: false,
                      onBack: () {},
                      child: ThemeSettingsPage(key: ValueKey(revision))))));
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.tap(find.text('配色方案'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final saved = Colors.teal.toARGB32().toRadixString(16);
      expect(GStorage.getSetting(SettingsKeys.themeColor), saved);
      expect(
          Theme.of(tester.element(find.byType(ThemeSettingsPage)))
              .colorScheme
              .primary,
          ThemeData(colorSchemeSeed: Colors.teal).colorScheme.primary);
      await Hive.box('setting').flush();
      revision++;
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.tap(find.text('配色方案'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<ThemePaletteDialog>(find.byType(ThemePaletteDialog))
              .selectedColor,
          saved);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(GStorage.getSetting(SettingsKeys.themeColor), saved);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
