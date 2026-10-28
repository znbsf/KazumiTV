import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/dialog/dialog.dart';
import 'package:kazumi/bean/widget/tv_app_shell.dart';
import 'package:kazumi/modules/plugin/plugin_http_module.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/plugin_editor/plugin_update_actions.dart';
import 'package:kazumi/pages/plugin_editor/rule_update_failure_dialog.dart';
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

Plugin _rule(String name, {String version = '1.0', bool enabled = true}) =>
    Plugin.fromTemplate()
      ..name = name
      ..version = version
      ..enabled = enabled;

PluginHTTPItem _catalog(String name) => PluginHTTPItem(
      name: name,
      version: '2.0',
      useNativePlayer: true,
      author: 'fixture',
      lastUpdate: 1,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform previousPaths;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('rule_update_failure_');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = previousPaths;
    await directory.delete(recursive: true);
  });
  tearDown(() => TvMode.setEnabledForTesting(false));

  test('old rules default to enabled and paused rules survive reload', () {
    final json = _rule('legacy').toJson()..remove('enabled');
    expect(Plugin.fromJson(json).enabled, isTrue);
    expect(Plugin.fromJson(_rule('paused', enabled: false).toJson()).enabled,
        isFalse);
  });

  test('batch reports exact failed names and excludes paused sources',
      () async {
    final downloads = <String>[];
    final slow = Completer<Plugin>();
    var writes = 0;
    final controller = PluginsController(
      catalogLoader: () async => [
        for (final name in ['slow', 'broken', 'new-client', 'paused'])
          _catalog(name),
      ],
      pluginLoader: (name) async {
        downloads.add(name);
        if (name == 'slow') return slow.future;
        if (name == 'broken') throw const FormatException('invalid payload');
        return _rule(name, version: '2.0')..api = '999';
      },
      pluginJsonWriter: (_) async => writes++,
      errorReporter: (_, __, ___) {},
    );
    controller.pluginList.addAll([
      _rule('SLOW'),
      _rule('broken'),
      _rule('new-client'),
      _rule('paused', enabled: false),
    ]);
    expect(await controller.checkPluginUpdatesOnStartup(enabled: true), 3);
    final pending = controller.tryUpdateAllPlugin(ensureCatalog: false);
    await Future<void>.delayed(Duration.zero);
    slow.complete(_rule('slow', version: '2.0'));
    final result = await pending;
    expect(result.candidates, 3);
    expect(result.updated, 1);
    expect(result.failed, 1);
    expect(result.requiresNewerClient, 1);
    expect(result.failedNames, ['broken']);
    expect(result.incompatibleNames, ['new-client']);
    expect(downloads, ['slow', 'broken', 'new-client']);
    expect(writes, 1);
    expect(controller.pluginList[1].version, '1.0');
  });

  test('pause persists, skips later startup checks, and can be restored',
      () async {
    late String saved;
    final controller = PluginsController(
      catalogLoader: () async => [_catalog('source')],
      pluginJsonWriter: (json) async => saved = json,
    )..pluginList.add(_rule('Source'));
    await controller.setPluginEnabled('SOURCE', false);
    expect((jsonDecode(saved) as List).single['enabled'], isFalse);
    expect(controller.enabledPlugins, isEmpty);
    expect(await controller.checkPluginUpdatesOnStartup(enabled: true), 0);
    expect((await controller.tryUpdateAllPlugin()).hasNoCandidates, isTrue);
    await controller.setPluginEnabled('source', true);
    expect(controller.enabledPlugins.single.name, 'Source');
    expect(await controller.checkPluginUpdatesOnStartup(enabled: true), 1);
  });

  test('failed persistence rolls back pause and removal', () async {
    final controller = PluginsController(
      pluginJsonWriter: (_) async => throw StateError('disk full'),
      errorReporter: (_, __, ___) {},
    )..pluginList.add(_rule('source'));
    await expectLater(
        controller.setPluginEnabled('source', false), throwsStateError);
    expect(controller.pluginList.single.enabled, isTrue);
    await expectLater(controller.removePlugins({'source'}), throwsStateError);
    expect(controller.pluginList.single.name, 'source');
  });

  test('failure catalog names can remove differently cased local source',
      () async {
    final controller = PluginsController(pluginJsonWriter: (_) async {})
      ..pluginList.addAll([_rule('BAD'), _rule('other')]);
    await controller.removePlugins({'bad'});
    expect(controller.pluginList.single.name, 'other');
  });

  test('new controller loads saved pause and excludes it from startup',
      () async {
    final folder = Directory('${directory.path}/plugins/v2');
    await folder.create(recursive: true);
    await File('${folder.path}/plugins.json').writeAsString(
      jsonEncode([_rule('source', enabled: false).toJson()]),
    );
    final reloaded = PluginsController(
      catalogLoader: () async => [_catalog('source')],
    );
    await reloaded.init();
    expect(reloaded.pluginList.single.enabled, isFalse);
    expect(await reloaded.checkPluginUpdatesOnStartup(enabled: true), 0);
  });

  test('manual update and reimport preserve local pause preference', () async {
    final controller = PluginsController(
      pluginLoader: (name) async => _rule(name, version: '2.0'),
      pluginJsonWriter: (_) async {},
    )..pluginList.add(_rule('source', enabled: false));
    expect(await controller.tryUpdatePluginByName('SOURCE'),
        PluginUpdateResult.updated);
    expect(controller.pluginList.single.version, '2.0');
    expect(controller.pluginList.single.enabled, isFalse);
    await controller.updatePlugin(_rule('source', version: '3.0'));
    expect(controller.pluginList.single.enabled, isFalse);
  });

  Future<FocusNode> mount(WidgetTester tester) async {
    TvMode.setEnabledForTesting(true);
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final focus = FocusNode();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: rootNavigatorKey,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      navigatorObservers: [KazumiDialog.observer],
      builder: (_, child) => TvAppShell(child: child!),
      home: Scaffold(
          body: TextButton(
        autofocus: true,
        focusNode: focus,
        onPressed: () {},
        child: const Text('home'),
      )),
    ));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      focus.dispose();
    });
    return focus;
  }

  testWidgets('single failure names source and remote OK retains it',
      (tester) async {
    final focus = await mount(tester);
    var writes = 0;
    final controller = PluginsController(
      pluginLoader: (_) async => throw const FormatException('broken'),
      pluginJsonWriter: (_) async => writes++,
      errorReporter: (_, __, ___) {},
    )..pluginList.add(_rule('失败的源'));
    final pending =
        updatePluginWithFeedback(controller, '失败的源', installing: false);
    await tester.pumpAndSettle();
    expect(find.text('失败的源'), findsOneWidget);
    expect(find.text('暂时停用'), findsOneWidget);
    expect(find.text('移除'), findsOneWidget);
    expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<TextButton>()
            ?.child,
        isA<Text>());
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(await pending, PluginUpdateResult.failed);
    expect(writes, 0);
    expect(controller.pluginList.single.enabled, isTrue);
    expect(focus.hasFocus, isTrue);
  });

  testWidgets(
      'batch failure offers pause per source without changing successful source',
      (tester) async {
    await mount(tester);
    final controller = PluginsController(
      catalogLoader: () async => [_catalog('bad'), _catalog('good')],
      pluginLoader: (name) async {
        if (name == 'bad') throw const FormatException('broken');
        return _rule(name, version: '2.0');
      },
      pluginJsonWriter: (_) async {},
      errorReporter: (_, __, ___) {},
    )..pluginList.addAll([_rule('bad'), _rule('good')]);
    final pending =
        updateAllPluginsWithFeedback(controller, ensureCatalog: true);
    await tester.pumpAndSettle();
    expect(find.text('bad'), findsOneWidget);
    expect(find.text('更新完成：成功 1 条，失败 1 条'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.pluginList.first.enabled, isFalse);
    expect(controller.pluginList.last.enabled, isTrue);
    expect(controller.pluginList.last.version, '2.0');
    await tester.tap(find.text('保留并关闭'));
    await tester.pumpAndSettle();
    await pending;
  });

  testWidgets('remove requires confirmation and cancel keeps source',
      (tester) async {
    await mount(tester);
    final controller = PluginsController(pluginJsonWriter: (_) async {})
      ..pluginList.add(_rule('bad'));
    final pending = showRuleUpdateFailures(controller,
        failedNames: ['bad'], incompatibleNames: [], summary: '更新失败');
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除'));
    await tester.pumpAndSettle();
    expect(find.text('删除这条规则？'), findsOneWidget);
    await tester.tap(find.text('保留'));
    await tester.pumpAndSettle();
    expect(controller.pluginList.single.name, 'bad');
    await tester.tap(find.text('移除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(controller.pluginList, isEmpty);
    expect(find.text('已移除'), findsOneWidget);
    await tester.tap(find.text('保留并关闭'));
    await tester.pumpAndSettle();
    await pending;
  });

  testWidgets('long failure lists scroll and preserve full source names',
      (tester) async {
    await mount(tester);
    final names = List.generate(16, (i) => '长名称故障来源$i：完整规则名称不可被截断');
    final controller = PluginsController(pluginJsonWriter: (_) async {})
      ..pluginList.addAll(names.map(_rule));
    final pending = showRuleUpdateFailures(controller,
        failedNames: names, incompatibleNames: [], summary: '失败 16 条');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(names.last));
    await tester.pumpAndSettle();
    expect(find.text(names.last).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('保留并关闭'));
    await tester.pumpAndSettle();
    await pending;
  });
}
