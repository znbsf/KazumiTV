import 'dart:convert';
import 'dart:io';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/services/storage/storage.dart';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/plugin_editor/editor_form_widgets.dart';
import 'package:kazumi/pages/plugin_editor/plugin_editor_page.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('api9_editor_');
    PathProviderPlatform.instance = _Paths(temp.path);
    Hive.init(temp.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });
  testWidgets('editor restores, validates and saves the API 9 detail template',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final writes = <String>[];
    final controller = PluginsController(pluginJsonWriter: (json) async {
      writes.add(json);
    });
    final plugin = Plugin.fromJson({
      'api': '9',
      'name': 'Editor fixture',
      'baseURL': 'https://example.invalid',
      'searchMode': 'api',
      'searchApiConfig': {
        'request': {'url': 'https://example.invalid/search'},
        'sourceTemplate': 'https://example.invalid/old/@source',
      },
    });
    controller.pluginList.add(plugin);
    final module = createModule(register: (c) {
      c.route('/',
          child: (context, _) => Scaffold(
              body: TextButton(
                  onPressed: () => context.pushNamed('/editor'),
                  child: const Text('Open editor'))));
      c.route('/editor',
          child: (_, __) => PluginEditorPage(
              plugin: controller.pluginList.single, controller: controller));
    });
    await tester.pumpWidget(ModularApp(
        module: module,
        initialRoute: '/',
        child: Builder(
            builder: (context) => MaterialApp.router(
                routerConfig: ModularApp.routerConfigOf(context)))));
    await tester.pumpAndSettle();
    Future<void> openSearch() async {
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('搜索').first);
      await tester.pumpAndSettle();
    }

    Finder field() => find.descendant(
        of: find.widgetWithText(EditorTextField, '详情页地址模板（URL，可选）'),
        matching: find.byType(EditableText));
    await openSearch();
    await tester.ensureVisible(field());
    expect(tester.widget<EditableText>(field()).controller.text,
        'https://example.invalid/old/@source');
    await tester.enterText(field(), 'https://example.invalid/fixed');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    expect(find.textContaining('必须引用 @source'), findsOneWidget);
    await tester.ensureVisible(field());
    await tester.enterText(field(), 'https://example.invalid/GV@source/');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(writes, hasLength(1));
    final saved = (jsonDecode(writes.single) as List).single;
    expect(saved['api'], '9');
    expect(saved['searchApiConfig']['sourceTemplate'],
        'https://example.invalid/GV@source/');
    await openSearch();
    expect(tester.widget<EditableText>(field()).controller.text,
        'https://example.invalid/GV@source/');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}
