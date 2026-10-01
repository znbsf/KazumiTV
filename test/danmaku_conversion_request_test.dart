import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/danmaku/danmaku_ch_convert.dart';
import 'package:kazumi/pages/settings/danmaku/danmaku_ch_convert_tile.dart';
import 'package:kazumi/request/apis/danmaku_api.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPaths;
  late _DanmakuAdapter adapter;

  setUpAll(() async {
    Logger.level = Level.off;
    directory =
        await Directory.systemTemp.createTemp('kazumi_conversion_test_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });

  setUp(() async {
    await GStorage.resetSettings([SettingsKeys.danmakuChConvert]);
    await GStorage.putSetting(SettingsKeys.enableBangumiProxy, false);
    DioFactory.reset();
    adapter = _DanmakuAdapter();
    DioFactory.apiDio.httpClientAdapter = adapter;
  });

  tearDown(() {
    DioFactory.apiDio.close(force: true);
    DioFactory.reset();
  });

  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    expect(
        directory.absolute.path.startsWith(Directory.systemTemp.absolute.path),
        isTrue);
    expect(directory.uri.pathSegments.where((part) => part.isNotEmpty).last,
        startsWith('kazumi_conversion_test_'));
    await directory.delete(recursive: true);
  });

  for (final mode in DanmakuChConvert.values) {
    test('automatic comment request sends conversion ${mode.value}', () async {
      await GStorage.putSetting(SettingsKeys.danmakuChConvert, mode.value);

      final entries = await DanmakuApi.getDanDanmaku(1758, 2);

      final request = adapter.requests.single;
      expect(request.uri.path, '${ApiEndpoints.dandanAPIComment}17580002');
      expect(request.queryParameters['withRelated'], 'true');
      expect(request.queryParameters['chConvert'], mode.value.toString());
      expect(entries.single.message, '缓存文字保持原样');
    });

    test('explicit episode request sends conversion ${mode.value}', () async {
      await GStorage.putSetting(SettingsKeys.danmakuChConvert, mode.value);

      await DanmakuApi.getDanDanmakuByEpisodeID(7654321);

      final request = adapter.requests.single;
      expect(request.uri.path, '${ApiEndpoints.dandanAPIComment}7654321');
      expect(request.queryParameters['withRelated'], 'true');
      expect(request.queryParameters['chConvert'], mode.value.toString());
    });
  }

  test('invalid persisted conversion falls back to unconverted requests',
      () async {
    await GStorage.putSetting(SettingsKeys.danmakuChConvert, 99);

    await DanmakuApi.getDanDanmakuByEpisodeID(1001);

    expect(adapter.requests.single.queryParameters['chConvert'], '0');
    expect(DanmakuChConvert.fromValue(-1), DanmakuChConvert.none);
  });

  test('unmatched anime returns empty without issuing a request', () async {
    await GStorage.putSetting(SettingsKeys.danmakuChConvert, 2);

    expect(await DanmakuApi.getDanDanmaku(0, 4), isEmpty);
    expect(adapter.requests, isEmpty);
  });

  test('manual search keeps v2 search parameters without comment conversion',
      () async {
    await GStorage.putSetting(SettingsKeys.danmakuChConvert, 2);
    adapter.response = {'animes': [], 'hasMore': false};

    await DanmakuApi.searchAnimes('测试标题');

    final request = adapter.requests.single;
    expect(request.uri.path, ApiEndpoints.dandanAPISearchEpisodes);
    expect(request.queryParameters, {'anime': '测试标题', 'v2': 'true'});
  });

  test('a failed comment request preserves the saved conversion', () async {
    await GStorage.putSetting(SettingsKeys.danmakuChConvert, 2);
    adapter.fail = true;

    await expectLater(
        DanmakuApi.getDanDanmakuByEpisodeID(1001), throwsA(anything));

    expect(GStorage.getSetting(SettingsKeys.danmakuChConvert), 2);
    expect(adapter.requests.single.queryParameters['chConvert'], '2');
  });

  test('conversion preference survives closing and reopening its Hive box',
      () async {
    var box = await Hive.openBox<dynamic>('conversion_preferences');
    await box.put(SettingsKeys.danmakuChConvert.name, 2);
    await box.close();

    box = await Hive.openBox<dynamic>('conversion_preferences');

    final value = SettingsKeys.danmakuChConvert.resolveStored(
        box.get(SettingsKeys.danmakuChConvert.name), const SettingContext());
    expect(DanmakuChConvert.fromValue(value), DanmakuChConvert.traditional);
    await box.deleteFromDisk();
  });

  test('resetting danmaku preferences restores conversion only in its group',
      () async {
    await GStorage.putSetting(SettingsKeys.danmakuChConvert, 2);
    await GStorage.putSetting(SettingsKeys.webDavEnableDanmakuShield, true);
    await GStorage.shieldList.put('保留规则', '保留规则');

    await GStorage.resetDanmakuSettings();

    expect(GStorage.getSetting(SettingsKeys.danmakuChConvert), 0);
    expect(GStorage.getSetting(SettingsKeys.webDavEnableDanmakuShield), isTrue);
    expect(GStorage.shieldList.values, contains('保留规则'));
    await GStorage.shieldList.clear();
  });

  testWidgets('menu saves conversion and reflects the persisted value',
      (tester) async {
    Future<void>? write;
    await tester.pumpWidget(_app(DanmakuChConvertTile(
      saveMode: (value) => write = tester.runAsync(() async {
        await GStorage.putSetting(SettingsKeys.danmakuChConvert, value);
        await Hive.box<dynamic>('setting').flush();
      }).then((_) {}),
    )));
    await tester.tap(find.text('简繁转换'));
    await tester.pumpAndSettle();
    // Keep input in the widget zone, but start disk IO in the injected save
    // callback's real-async zone. Menu activation is scheduled by a frame.
    await tester.tap(find.widgetWithText(MenuItemButton, '转为繁体'));
    await tester.pump();
    await write!;
    await tester.pumpAndSettle();

    expect(GStorage.getSetting(SettingsKeys.danmakuChConvert), 2);
    expect(find.text('转为繁体'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed menu persistence keeps the prior value and allows retry',
      (tester) async {
    var attempts = 0;
    Future<void>? write;
    await tester.pumpWidget(_app(DanmakuChConvertTile(saveMode: (value) {
      attempts++;
      if (attempts == 1) {
        return Future<void>.error(
            StateError('simulated settings write failure'));
      }
      return write = tester.runAsync(() async {
        await GStorage.putSetting(SettingsKeys.danmakuChConvert, value);
        await Hive.box<dynamic>('setting').flush();
      }).then((_) {});
    })));
    await tester.tap(find.text('简繁转换'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, '转为简体'));
    await tester.pumpAndSettle();

    expect(GStorage.getSetting(SettingsKeys.danmakuChConvert), 0);
    expect(find.text('简繁转换设置保存失败，请重试'), findsOneWidget);

    await tester.tap(find.text('简繁转换'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, '转为简体'));
    await tester.pump();
    await write!;
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(GStorage.getSetting(SettingsKeys.danmakuChConvert), 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pending menu writes reject duplicate selections',
      (tester) async {
    final pending = Completer<void>();
    final values = <int>[];
    Future<void>? write;
    await tester.pumpWidget(_app(DanmakuChConvertTile(saveMode: (value) {
      values.add(value);
      return write = pending.future.then(
          (_) => GStorage.putSetting(SettingsKeys.danmakuChConvert, value));
    })));
    await tester.tap(find.text('简繁转换'));
    await tester.pumpAndSettle();
    final simplified = tester
        .widget<MenuItemButton>(find.widgetWithText(MenuItemButton, '转为简体'));
    final traditional = tester
        .widget<MenuItemButton>(find.widgetWithText(MenuItemButton, '转为繁体'));

    await tester.runAsync(() async {
      simplified.onPressed!();
      traditional.onPressed!();
      expect(values, [1]);
      expect(GStorage.getSetting(SettingsKeys.danmakuChConvert), 0);
      pending.complete();
      await write!;
      await Hive.box<dynamic>('setting').flush();
    });
    await tester.pumpAndSettle();
    expect(GStorage.getSetting(SettingsKeys.danmakuChConvert), 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('settings menu opens and selects using keyboard focus',
      (tester) async {
    Future<void>? write;
    await tester.pumpWidget(_app(DanmakuChConvertTile(
      saveMode: (value) => write = tester.runAsync(() async {
        await GStorage.putSetting(SettingsKeys.danmakuChConvert, value);
        await Hive.box<dynamic>('setting').flush();
      }).then((_) {}),
    )));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(MenuItemButton, '转为简体'), findsOneWidget);

    // Enter the menu's first option, then traverse to simplified conversion.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await write!;
    await tester.pumpAndSettle();
    expect(GStorage.getSetting(SettingsKeys.danmakuChConvert), 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Widget _app(Widget tile) => MaterialApp(
      home: Scaffold(body: Column(children: [tile])),
    );

class _DanmakuAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  bool fail = false;
  Map<String, dynamic> response = {
    'comments': [
      {'p': '1.5,1,16777215,[Test]', 'm': '缓存文字保持原样'}
    ],
  };

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (fail) {
      throw DioException.connectionError(
          requestOptions: options, reason: 'simulated connection failure');
    }
    return ResponseBody.fromString(jsonEncode(response), 200, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}
