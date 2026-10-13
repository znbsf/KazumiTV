import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/widget/tv_text_entry.dart';
import 'package:kazumi/bean/widget/tv_focusable_surface.dart';
import 'package:kazumi/pages/plugin_editor/plugin_catalog_view.dart';
import 'package:kazumi/pages/plugin_editor/plugin_view_page.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('kazumi_rule_input_');
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });
  for (final shop in [false, true]) {
    testWidgets(
        '${shop ? 'catalog' : 'installed rules'} empty filter commit clear and Back return to entry',
        (tester) async {
      TvMode.setEnabledForTesting(true);
      addTearDown(() => TvMode.setEnabledForTesting(false));
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = PluginsController(catalogLoader: () async => []);
      await controller.ensurePluginCatalog();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: shop
                  ? PluginCatalogView(controller: controller)
                  : PluginViewPage(controller: controller))));
      await tester.pumpAndSettle();
      final entry = find.byType(TvTextEntry);
      final surface = tester.widget<TvFocusableSurface>(find.descendant(
          of: entry, matching: find.byType(TvFocusableSurface)));
      surface.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, false);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, false);
      surface.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('tv-text-editor')), 'no such rule');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(surface.focusNode!.hasFocus, true);
      expect(tester.widget<TvTextEntry>(entry).child.controller!.text,
          'no such rule');
      await tester.tap(
          find.descendant(of: entry, matching: find.byType(IconButton)).first);
      await tester.pumpAndSettle();
      expect(tester.widget<TvTextEntry>(entry).child.controller!.text, '');
      surface.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(surface.focusNode!.hasFocus, true);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
