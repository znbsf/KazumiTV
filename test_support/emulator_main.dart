// Device-only fixture entry point. Never the product entry point.
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

const base = 'http://10.0.2.2:18791';
Map<String, dynamic> subject(int id) => {
      'id': id,
      'type': 2,
      'name': 'Fixture $id',
      'name_cn': 'Fixture $id',
      'summary': List.filled(8, 'Synthetic emulator fixture. No live provider.')
          .join('\n'),
      'date': '2026-09-06',
      'air_weekday': 1,
      'images': {
        'large': '$base/poster.png',
        'common': '$base/poster.png',
        'medium': '$base/poster.png'
      },
      'tags': <dynamic>[],
      'eps': 201,
      'rating': {
        'rank': id,
        'score': 8.0,
        'total': 100,
        'count': List.filled(10, 10)
      },
    };
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
    dynamic data;
    if (path.contains('calendar')) {
      data = {
        for (int i = 1; i <= 7; i++)
          '$i': List.generate(8, (j) => {'subject': subject(j + 1)})
      };
    } else if (path.contains('/subjects/') && !path.contains('/search')) {
      final id = int.tryParse(path.split('/').last) ?? 1;
      data = subject(id);
    } else if (path.contains('search') || path.contains('/popular/subjects')) {
      data = {'total': 24, 'data': List.generate(24, (j) => subject(j + 1))};
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
