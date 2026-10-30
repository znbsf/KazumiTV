// Explicit remoteqa fixture. Production main never imports this entrypoint.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_ce/hive.dart';
// ignore: depend_on_referenced_packages
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/tv_app_shell.dart';
import 'package:kazumi/modules/plugin/plugin_http_module.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/plugin_editor/plugin_update_actions.dart';
import 'package:kazumi/pages/plugin_editor/plugin_view_page.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/storage/storage.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

const names = ['测试来源甲', '测试来源乙', '新版客户端来源'];
Plugin rule(String name, {String version = '1.0'}) => Plugin.fromTemplate()
  ..name = name
  ..version = version
  ..baseUrl = 'https://example.invalid';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if ((await PackageInfo.fromPlatform()).packageName !=
      'com.znbsf.kazumi.fluttertv.remoteqa') {
    throw StateError('Requires remoteqa identity');
  }
  await TvMode.initialize();
  if (!TvMode.enabled) throw StateError('Requires TV mode');
  final root =
      '${(await getApplicationSupportDirectory()).path}/rules-20261030';
  await Directory('$root/hive').create(recursive: true);
  PathProviderPlatform.instance = _Paths(root);
  Hive.init('$root/hive');
  await GStorage.init();
  final controller = PluginsController(
    catalogLoader: () async => [
      for (final name in names)
        PluginHTTPItem(
            name: name,
            version: '2.0',
            useNativePlayer: true,
            author: 'Local fixture',
            lastUpdate: 1),
    ],
    pluginLoader: (name) async {
      if (name == names.last) return rule(name, version: '2.0')..api = '999';
      throw const FormatException('Controlled rule download failure');
    },
    errorReporter: (_, __, ___) {},
  );
  await controller.init();
  final marker = File('$root/seeded');
  if (!await marker.exists()) {
    await controller.updatePlugins(names.map(rule).toList());
    await marker.writeAsString('seeded once; preserve subsequent changes');
  }
  await controller.ensurePluginCatalog();
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  runApp(MaterialApp(
    navigatorKey: rootNavigatorKey,
    scaffoldMessengerKey: rootScaffoldMessengerKey,
    navigatorObservers: [KazumiDialog.observer, rootRouteObserver],
    theme: ThemeData.dark(useMaterial3: true),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('zh', 'CN')],
    locale: const Locale('zh', 'CN'),
    builder: (_, child) => TvAppShell(child: child!),
    home: _Home(controller),
  ));
}

class _Home extends StatefulWidget {
  const _Home(this.controller);
  final PluginsController controller;
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('规则失败验收 · 隔离数据')),
        body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('生产控制器与页面；本地模拟下载失败，不请求真实来源'),
          const SizedBox(height: 20),
          Text(widget.controller.pluginList
              .map((p) => '${p.name}：${p.enabled ? '启用' : '停用'}')
              .join('\n')),
          const SizedBox(height: 20),
          FilledButton(
              autofocus: true,
              onPressed: () async {
                await updateAllPluginsWithFeedback(widget.controller,
                    ensureCatalog: true);
                if (mounted) setState(() {});
              },
              child: const Text('检查更新并处理失败')),
          const SizedBox(height: 12),
          FilledButton(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) =>
                        PluginViewPage(controller: widget.controller)));
                if (mounted) setState(() {});
              },
              child: const Text('打开生产规则管理')),
        ])),
      );
}
