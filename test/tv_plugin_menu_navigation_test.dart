import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/plugin/plugin_http_module.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/plugin_editor/plugin_catalog_view.dart';
import 'package:kazumi/pages/plugin_editor/plugin_shop_page.dart';
import 'package:kazumi/pages/plugin_editor/plugin_view_page.dart';
import 'package:kazumi/pages/settings/settings_page.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _MissingFilePicker extends FilePicker {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    expect(type, FileType.custom);
    expect(allowedExtensions, ['json']);
    throw PlatformException(code: 'invalid_format_type');
  }
}

class _Fixture {
  int writes = 0;
  int downloads = 0;
  final nav = GlobalKey<NavigatorState>();
  late final controller = PluginsController(
    catalogLoader: () async => [
      for (final name in ['Menu fixture', 'Second fixture'])
        PluginHTTPItem(
            name: name,
            version: '1.0.0',
            useNativePlayer: true,
            author: 'fixture',
            lastUpdate: 1),
    ],
    pluginLoader: (_) async {
      downloads++;
      throw StateError('Menu navigation must not download a rule');
    },
    pluginJsonWriter: (_) async {
      writes++;
    },
  );

  Future<void> mount(WidgetTester tester, {required bool shop}) async {
    TvMode.setEnabledForTesting(true);
    addTearDown(() => TvMode.setEnabledForTesting(false));
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final name in ['Menu fixture', 'Second fixture']) {
      controller.pluginList.add(Plugin.fromTemplate()
        ..name = name
        ..version = '1.0.0'
        ..baseUrl = 'https://example.invalid');
    }
    await controller.ensurePluginCatalog();
    await tester.pumpWidget(ModularApp(
      navigatorKey: nav,
      navigatorObservers: [KazumiDialog.observer],
      module: createModule(register: (c) {
        c.route('/tab/my',
            child: (_, __) => const Scaffold(body: Text('My fixture')));
        c.route('/settings',
            child: (_, state) => SettingsPage(location: state.uri.path),
            children: (sub) {
              sub.route('/plugin',
                  child: (_, __) => PluginViewPage(controller: controller));
              sub.route('/plugin/shop',
                  child: (_, __) => PluginShopPage(controller: controller));
            });
      }),
      initialRoute: shop ? '/settings/plugin/shop' : '/settings/plugin',
      child: Builder(
          builder: (context) => MaterialApp.router(
              scaffoldMessengerKey: rootScaffoldMessengerKey,
              routerConfig: ModularApp.routerConfigOf(context))),
    ));
    await tester.pumpAndSettle();
  }

  Future<FocusNode> open(WidgetTester tester, {required bool shop}) async {
    final trigger = shop
        ? find.descendant(
            of: find.byType(PluginCatalogView), matching: find.text('最近更新'))
        : find.byTooltip('Menu fixture 的更多操作');
    await tester.ensureVisible(trigger);
    await tester.pumpAndSettle();
    final descendant = shop
        ? trigger
        : find.descendant(
            of: trigger, matching: find.byIcon(Icons.more_horiz_rounded));
    final focus = Focus.of(tester.element(descendant));
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsWidgets);
    return focus;
  }

  void expectUnchanged() {
    expect(controller.pluginList.map((p) => p.name).toList(),
        ['Menu fixture', 'Second fixture']);
    expect(writes, 0);
    expect(downloads, 0);
  }
}

bool _inMenu() =>
    FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<MenuItemButton>() !=
    null;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform oldPaths;
  setUpAll(() async {
    oldPaths = PathProviderPlatform.instance;
    directory = await Directory.systemTemp.createTemp('tv_plugin_menu_');
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = oldPaths;
    await directory.delete(recursive: true);
  });

  testWidgets('D05 missing file picker offers named alternative imports', (
    tester,
  ) async {
    FilePicker? original;
    try {
      original = FilePicker.platform;
    } catch (_) {
      // The platform registrant is absent in some widget test hosts.
    }
    FilePicker.platform = _MissingFilePicker();
    addTearDown(() => FilePicker.platform = original ?? FilePickerIO());
    final fixture = _Fixture();
    await fixture.mount(tester, shop: false);
    await tester.tap(find.widgetWithText(FilledButton, '添加规则'));
    await tester.pumpAndSettle();
    expect(find.text('从剪贴板导入'), findsOneWidget);
    expect(find.text('浏览规则仓库'), findsOneWidget);
    await tester.tap(find.text('从文件导入'));
    await tester.pumpAndSettle();
    final toast = find.byType(SnackBar);
    expect(toast, findsOneWidget);
    expect(
      find.descendant(
        of: toast,
        matching: find.text('这台设备没有系统文件选择器，请改用“从剪贴板导入”或“浏览规则仓库”'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('PlatformException'), findsNothing);
    fixture.expectUnchanged();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  for (final shop in [false, true]) {
    final pageType = shop ? PluginShopPage : PluginViewPage;
    final label = shop ? 'catalog sort' : 'installed rule actions';
    testWidgets('$label focuses menu and keeps arrows inside', (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester, shop: shop);
      await fixture.open(tester, shop: shop);
      expect(_inMenu(), isTrue, reason: 'OK must focus an enabled menu item');
      for (final key in [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowUp
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(_inMenu(), isTrue,
            reason: 'arrows must not reach the page behind the menu');
      }
      fixture.expectUnchanged();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });

    testWidgets('$label Android Back closes only menu and restores trigger',
        (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester, shop: shop);
      final trigger = await fixture.open(tester, shop: shop);
      // Independent of automatic focus: exercise the root Android dispatcher.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(pageType), findsOneWidget,
          reason: 'system Back must keep the current settings page');
      expect(find.byType(MenuItemButton), findsNothing);
      expect(trigger.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_inMenu(), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
      expect(trigger.hasPrimaryFocus, isTrue);
      fixture.expectUnchanged();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'installed rule menu pauses and restores source with remote confirm',
      (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester, shop: false);
    await fixture.open(tester, shop: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(fixture.controller.pluginList.first.enabled, isFalse);
    expect(find.text('已暂时停用'), findsOneWidget);
    expect(fixture.writes, 1);
    await fixture.open(tester, shop: false);
    expect(find.text('恢复启用'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(fixture.controller.pluginList.first.enabled, isTrue);
    expect(find.text('已暂时停用'), findsNothing);
    expect(fixture.writes, 2);
    expect(fixture.downloads, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'pushed catalogue menu Back stays in shop before next Back leaves',
      (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester, shop: false);
    final browse = find.text('规则仓库');
    await tester.ensureVisible(browse);
    await tester.pumpAndSettle();
    final browseFocus = Focus.of(tester.element(browse));
    browseFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(PluginShopPage), findsOneWidget);
    final nested = Navigator.of(tester.element(find.byType(PluginCatalogView)));
    expect(nested.canPop(), isTrue,
        reason: 'must be a real pushed shop, not initialRoute');
    final trigger = await fixture.open(tester, shop: true);
    expect(_inMenu(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_inMenu(), isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PluginShopPage), findsOneWidget,
        reason: 'first system Back must consume shop-local menu history');
    expect(find.byType(MenuItemButton), findsNothing);
    expect(trigger.hasPrimaryFocus, isTrue);
    expect(nested.canPop(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_inMenu(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(trigger.hasPrimaryFocus, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PluginShopPage), findsNothing);
    expect(find.byType(PluginViewPage), findsOneWidget);
    expect(browseFocus.hasPrimaryFocus, isTrue);
    fixture.expectUnchanged();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
