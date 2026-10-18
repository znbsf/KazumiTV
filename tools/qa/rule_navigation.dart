// Isolated local-only navigation fixture. Never imported by production main.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:mobx/mobx.dart';
// ignore: depend_on_referenced_packages
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kazumi/bean/card/rule_card.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/tv_app_shell.dart';
import 'package:kazumi/modules/plugin/plugin_http_module.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/onboarding/steps/plugin_shop_step.dart';
import 'package:kazumi/pages/plugin_editor/plugin_catalog_view.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/storage/storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode ||
      (await PackageInfo.fromPlatform()).packageName !=
          'com.znbsf.kazumi.fluttertv.featureqa') {
    throw StateError('Requires isolated featureqa debug identity');
  }
  await TvMode.initialize();
  if (!TvMode.enabled) throw StateError('Requires TV flavor');
  final root = await getApplicationSupportDirectory();
  await Hive.initFlutter('${root.path}/hive');
  await GStorage.init();
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
    home: const _NavigationQa(),
  ));
}

String _name(int number) => '本地规则 ${number.toString().padLeft(2, '0')}';
List<PluginHTTPItem> _fixtures() => List.generate(
    40,
    (index) => PluginHTTPItem(
          name: _name(index + 1),
          version: '1.0.0',
          useNativePlayer: true,
          author: 'Local navigation QA',
          lastUpdate: 1800000000 - index,
        ));

class _LocalController extends PluginsController {
  _LocalController() : super(catalogLoader: () async => _fixtures()) {
    runInAction(() {
      pluginHTTPList.addAll(_fixtures());
      for (var number = 8; number <= 33; number++) {
        _installed.add(_name(number));
      }
    });
  }
  final _installed = ObservableSet<String>();
  @override
  bool get isPluginCatalogFresh => true;
  @override
  Future<List<PluginHTTPItem>> ensurePluginCatalog() async =>
      pluginHTTPList.toList();
  @override
  Future<List<PluginHTTPItem>> refreshPluginCatalog() async {
    debugPrint('NAV_QA local_refresh');
    return pluginHTTPList.toList();
  }

  @override
  PluginCatalogItemStatus pluginStatus(PluginHTTPItem item) =>
      _installed.contains(item.name)
          ? PluginCatalogItemStatus.installed
          : PluginCatalogItemStatus.install;
  @override
  Future<PluginUpdateResult> tryUpdatePluginByName(String name) async {
    runInAction(() => _installed.add(name));
    debugPrint('NAV_QA memory_install $name');
    return PluginUpdateResult.updated;
  }

  @override
  Future<PluginBatchUpdateResult> tryUpdateAllPlugin(
          {bool ensureCatalog = true}) async =>
      const PluginBatchUpdateResult(
          candidates: 0,
          updated: 0,
          requiresNewerClient: 0,
          failed: 0,
          notNewer: 0);
}

class _NavigationQa extends StatefulWidget {
  const _NavigationQa();
  @override
  State<_NavigationQa> createState() => _NavigationQaState();
}

class _NavigationQaState extends State<_NavigationQa> {
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_logFocus);
  }

  void _logFocus() {
    final node = FocusManager.instance.primaryFocus;
    String? rule;
    node?.context?.visitAncestorElements((element) {
      if (element.widget is RuleCard) {
        rule = (element.widget as RuleCard).title;
        return false;
      }
      return true;
    });
    debugPrint('NAV_QA focus ${rule ?? node?.debugLabel ?? 'none'}');
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_logFocus);
    super.dispose();
  }

  void _open(bool onboarding) {
    final controller = _LocalController();
    debugPrint(
        'NAV_QA open ${onboarding ? 'PluginShopStep' : 'PluginCatalogView'} count=40 installed=08..33');
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (context) => Scaffold(
              appBar: AppBar(
                  title: Text(onboarding
                      ? '规则导航 QA · PluginShopStep'
                      : '规则导航 QA · PluginCatalogView')),
              body: Column(children: [
                Expanded(
                    child: onboarding
                        ? PluginShopStep(controller: controller)
                        : PluginCatalogView(controller: controller)),
                SafeArea(
                    top: false,
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                  onPressed: () {
                                    debugPrint('NAV_QA footer_return');
                                    Navigator.pop(context);
                                  },
                                  child: const Text('返回')),
                              const SizedBox(width: 16),
                              FilledButton(
                                  onPressed: () {
                                    debugPrint('NAV_QA footer_confirm');
                                    Navigator.pop(context);
                                  },
                                  child: const Text('确认并返回')),
                            ]))),
              ]),
            )));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('规则导航 QA · 纯本地40条')),
        body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('08–33为连续已安装规则；安装仅改本次页面内存。\n直接组件验收，不进入协议或完整引导，不请求网络。'),
          const SizedBox(height: 24),
          FilledButton(
              autofocus: true,
              onPressed: () => _open(true),
              child: const Text('打开 PluginShopStep')),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: () => _open(false),
              child: const Text('打开 PluginCatalogView')),
        ])),
      );
}
