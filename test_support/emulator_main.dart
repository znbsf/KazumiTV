// Only for this task's isolated AVD. Never install on a real device or publish
// as the product entry point. All titles/images below are controlled samples,
// not real anime or evidence of public-provider availability.
// All application pages, repositories, source parsing, WebView extraction,
// MediaKit/MPV, platform channels and Compose Activity are production code.
// Only catalog metadata transport and installed test-source data are controlled.
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/app_module.dart';
import 'package:kazumi/app_widget.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/settings/theme_provider.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/network/metered_network_service.dart';
import 'package:kazumi/services/network/proxy_manager.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/platform/webview_feature_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

const base = 'http://10.0.2.2:18801';
const catalogSize = 96;

Map<String, dynamic> subject(int id, {bool detail = false}) => {
      'id': id,
      'type': 2,
      'name': '受控样本 $id · 本地界面验收',
      'name_cn': '受控样本 $id · 本地界面验收',
      'summary': id.isOdd
          ? List.filled(8, '受控样本 $id：这是本地模拟器的长简介，用于核对折叠、行高和封面连续性；非真实番剧。')
              .join('\n')
          : '受控样本 $id：短简介，仅用于本地模拟器界面验收，非真实番剧。',
      'date': '2026-09-06',
      'air_weekday': 1,
      'images': {
        // TV cards/home use medium; details use the distinct input large URL.
        // The attach refresh intentionally preserves input images. Large waits
        // one second, so the existing medium cover must remain visible meanwhile.
        'large': '$base/more-poster/$id.png',
        'common': '$base/poster/$id.png',
        'medium': '$base/poster/$id.png'
      },
      'tags': <dynamic>[],
      'eps': 201,
      'rating': {
        'rank': id,
        'score': 8.0,
        // Keep catalog summaries visible, but omit catalog vote statistics so
        // the real InfoPage refreshes via its existing missing-votes rule.
        // Only the detail response supplies the complete distribution. Both
        // responses keep the same large URL, preserving the attach protocol.
        if (detail) 'total': 100,
        if (detail) 'count': List.filled(10, 10)
      },
    };

int paginationValue(dynamic value, int fallback) =>
    int.tryParse(value?.toString() ?? '') ?? fallback;

Map<String, dynamic> catalogPage(RequestOptions options,
    {bool wrapSubjects = false}) {
  final query = {...options.uri.queryParameters, ...options.queryParameters};
  final offset =
      paginationValue(query['offset'], 0).clamp(0, catalogSize).toInt();
  final limit =
      paginationValue(query['limit'], 24).clamp(1, catalogSize).toInt();
  final remaining = catalogSize - offset;
  final count = remaining < limit ? remaining : limit;
  final items = List.generate(count, (index) => subject(offset + index + 1));
  return {
    'total': catalogSize,
    'limit': limit,
    'offset': offset,
    'data':
        wrapSubjects ? items.map((item) => {'subject': item}).toList() : items,
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await TvMode.initialize();
  if (!TvMode.enabled) {
    throw StateError('Fixture requires an isolated TV flavor.');
  }
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await WebViewFeatureService.initialize();
  final support = await getApplicationSupportDirectory();
  await Hive.initFlutter('${support.path}/hive');
  await GStorage.init();
  // Do not clear history: a force-stop/restart tests the real persistent resume.
  await GStorage.putSetting(SettingsKeys.autoUpdate, false);
  await GStorage.putSetting(SettingsKeys.checkPluginUpdateOnStartup, false);
  await GStorage.putSetting(SettingsKeys.bangumiSyncEnable, false);
  await GStorage.putSetting(SettingsKeys.webDavEnable, false);
  // This changes only the new AVD's fixture app settings. Use the existing
  // offset/limit mirror route for deterministic category pagination; its
  // metadata transport is intercepted below, so it makes no mirror request.
  await GStorage.putSetting(SettingsKeys.enableBangumiProxy, true);
  if (const bool.fromEnvironment('KAZUMI_FIXTURE_DEFAULT_OUTPUT')) {
    // Reset only this task's test-package settings so the device exercises
    // production auto selection rather than the previous explicit GPU run.
    await GStorage.putSetting(SettingsKeys.androidVideoRenderer, 'auto');
    await GStorage.putSetting(SettingsKeys.hAenable, true);
    await GStorage.putSetting(SettingsKeys.playerDebugMode, true);
  }
  if (const bool.fromEnvironment('KAZUMI_FIXTURE_SOFTWARE_OUTPUT')) {
    // Explicit second run isolates the virtual MediaCodec Surface path.
    // This changes only the newly created test package's application settings.
    await GStorage.putSetting(SettingsKeys.androidVideoRenderer, 'gpu');
    await GStorage.putSetting(SettingsKeys.hAenable, false);
  }
  final plugins = <Plugin>[];
  for (final name in ['fixture-primary', 'fixture-secondary']) {
    plugins.add(Plugin.fromTemplate()
      ..name = name
      ..version = '1.0'
      ..baseUrl = base
      ..searchURL = '$base/search?source=$name&q=@keyword'
      ..searchList = '//article'
      ..searchName = '//a'
      ..searchResult = '//a'
      ..chapterRoads = '//div[@class="road"]'
      ..chapterResult = '//a');
  }
  final file = File('${support.path}/plugins/v2/plugins.json');
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode(plugins.map((p) => p.toJson()).toList()));
  await MeteredNetworkService.refresh();
  ProxyManager.applyProxy();
  DioFactory.apiDio.interceptors.insert(0,
      InterceptorsWrapper(onRequest: (options, handler) {
    final path = options.uri.path;
    final detail = RegExp(r'/subjects/(\d+)$').firstMatch(path);
    dynamic data;
    if (path.contains('calendar')) {
      data = {
        for (int i = 1; i <= 7; i++)
          '$i':
              List.generate(8, (j) => {'subject': subject((i - 1) * 8 + j + 1)})
      };
    } else if (detail != null) {
      final id = int.parse(detail.group(1)!).clamp(1, catalogSize).toInt();
      data = subject(id, detail: true);
    } else if (path.endsWith('/trending/subjects')) {
      // The official Next API wraps each item under `subject`; the mirror and
      // search APIs return plain subjects. Keep their real response shapes.
      data = catalogPage(options, wrapSubjects: true);
    } else if (path.contains('search') || path.contains('/popular/subjects')) {
      data = catalogPage(options);
    } else if (path.endsWith('/subjects') ||
        path.endsWith('/characters') ||
        path.endsWith('/persons')) {
      data = <dynamic>[];
    } else {
      data = {'total': 0, 'data': <dynamic>[]};
    }
    handler.resolve(
        Response(requestOptions: options, statusCode: 200, data: data));
  }));
  runApp(ModularApp(
      module: appModule,
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [KazumiDialog.observer, rootRouteObserver],
      defaultTransition: TransitionType.material,
      provide: (scoped) =>
          scoped.addChangeNotifier<ThemeProvider>(ThemeProvider.new),
      child: const AppWidget()));
}
