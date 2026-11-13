import 'dart:async';
import 'dart:io';
import 'package:dio/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/modules/plugin/plugin_http_module.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/pages/plugin_editor/plugin_shop_page.dart';
import 'package:kazumi/services/plugin/plugin_cookie_manager.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late PathProviderPlatform paths;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('kazumi_rule_transport_');
    paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = paths;
    await dir.delete(recursive: true);
  });
  test(
      'XPath chapter request carries verified cookie and UA through same-origin redirect only',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final root = 'http://127.0.0.1:${server.port}';
    final captured = <String, String?>{};
    other.listen((request) async {
      captured['cross'] = request.headers.value('cookie');
      request.response.write('<ul><a href="/episode">one</a></ul>');
      await request.response.close();
    });
    server.listen((request) async {
      captured[request.uri.path] = request.headers.value('cookie');
      captured['ua'] = request.headers.value('user-agent');
      if (request.uri.path == '/same' || request.uri.path == '/cross') {
        request.response.statusCode = 302;
        request.response.headers.set(
            'location',
            request.uri.path == '/same'
                ? '/final'
                : 'http://127.0.0.1:${other.port}/final');
      } else {
        request.response.write('<ul><a href="/episode">one</a></ul>');
      }
      await request.response.close();
    });
    DioFactory.pluginDio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () => HttpOverrides.runWithHttpOverrides(
            () => HttpClient()..findProxy = (_) => 'DIRECT', _LocalHttp()));
    final plugin = Plugin.fromJson({
      'name': 'cookie-fixture',
      'api': '9',
      'baseURL': root,
      'chapterRoads': '//ul',
      'chapterResult': '//a'
    });
    await PluginCookieManager.instance.saveFromWebView(
        plugin.name, '$root/verify', 'session=fixture',
        userAgent: 'Verified-UA');
    try {
      await plugin.traceChapters('/same');
      expect(captured['/same'], 'session=fixture');
      expect(captured['/final'], 'session=fixture');
      expect(captured['ua'], 'Verified-UA');
      await plugin.traceChapters('/cross');
      expect(captured['cross'], isNull);
      await PluginCookieManager.instance.saveFromWebView(
          'secure', 'https://example.invalid/verify', 'session=secure');
      expect(
          await PluginCookieManager.instance.loadForRequest(
              'secure', Uri.parse('https://sub.example.invalid/')),
          isEmpty);
      expect(
          await PluginCookieManager.instance
              .loadForRequest('secure', Uri.parse('http://example.invalid/')),
          isEmpty);
    } finally {
      DioFactory.pluginDio.close(force: true);
      DioFactory.reset();
      await server.close(force: true);
      await other.close(force: true);
    }
  });
  test('repository changes invalidate an old catalog even after switching back',
      () async {
    final old = Completer<List<PluginHTTPItem>>();
    var calls = 0;
    final controller = PluginsController(catalogLoader: () {
      calls++;
      return calls == 1 ? old.future : Future.value([]);
    });
    final pending = controller.refreshPluginCatalog();
    await controller.setRuleRepository('https://example.invalid/rules/');
    await controller.setRuleRepository('');
    await controller.refreshPluginCatalog();
    old.complete([
      PluginHTTPItem.fromJson({
        'name': 'stale',
        'version': '1.0',
        'author': 'fixture',
        'lastUpdate': 1,
        'useNativePlayer': true
      })
    ]);
    await pending;
    expect(controller.pluginHTTPList, isEmpty);
    expect(calls, 2);
  });
  testWidgets(
      'repository dialog saves and restores official source using keyboard actions',
      (tester) async {
    final controller = _WidgetController(tester);
    await tester
        .pumpWidget(MaterialApp(home: PluginShopPage(controller: controller)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('设置规则仓库'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        'https://example.invalid/rules/index.json');
    final save = Focus.of(tester.element(find.text('保存')));
    save.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await controller.pending;
    await tester.pumpAndSettle();
    expect(controller.ruleRepository, 'https://example.invalid/rules/');
    await tester.tap(find.byTooltip('设置规则仓库'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复官方'));
    await controller.pending;
    await tester.pumpAndSettle();
    expect(controller.ruleRepository, isEmpty);
  });
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _LocalHttp extends HttpOverrides {}

class _WidgetController extends PluginsController {
  _WidgetController(this.tester) : super(catalogLoader: () async => []);
  final WidgetTester tester;
  Future<bool>? pending;
  @override
  Future<bool> setRuleRepository(String input) =>
      pending = tester.runAsync(() async {
        final changed = await super.setRuleRepository(input);
        await Hive.box<dynamic>('setting').flush();
        return changed;
      }).then((value) => value!);
}
