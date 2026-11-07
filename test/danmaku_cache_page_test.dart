import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/pages/settings/danmaku/danmaku_cache_page.dart';
import 'package:kazumi/services/danmaku/danmaku_cache_service.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Cache extends DanmakuCacheService {
  var clears = 0;
  var resizes = 0;
  @override
  Future<Map<String, int>> stats() async => {
        'entries': clears == 0 ? 100 : 0,
        'bytes': clears == 0 ? 10 * 1024 * 1024 : 0
      };
  @override
  Future<void> clear() async {
    clears++;
  }

  @override
  Future<void> resize() async {
    resizes++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late PathProviderPlatform oldPaths;
  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('kazumi_danmaku_page_');
    oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
    Hive.init(root.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = oldPaths;
    expect(root.absolute.path.startsWith(Directory.systemTemp.absolute.path),
        isTrue);
    expect(root.uri.pathSegments.where((s) => s.isNotEmpty).last,
        startsWith('kazumi_danmaku_page_'));
    await root.delete(recursive: true);
  });

  testWidgets(
      'TV cache settings show independent quota and clear by remote after confirmation',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    addTearDown(() => TvMode.setEnabledForTesting(false));
    final cache = _Cache();
    tester.view.physicalSize = const Size(1280, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: DanmakuCachePage(cache: cache)));
    await tester.pumpAndSettle();
    expect(GStorage.getSetting(SettingsKeys.danmakuCacheEnabled), isTrue);
    expect(GStorage.getSetting(SettingsKeys.recentVideoCacheEnabled), isFalse);
    expect(find.text('100 条 · 10.0 MiB'), findsOneWidget);
    expect(find.text('256 MiB'), findsOneWidget);
    final clear = find.text('清除弹幕缓存');
    await tester.ensureVisible(clear);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(cache.clears, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(cache.clears, 1);
    expect(find.text('0 条 · 0.0 MiB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('capacity and switch persist without enabling video caching',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    addTearDown(() => TvMode.setEnabledForTesting(false));
    final cache = _Cache();
    await tester.pumpWidget(MaterialApp(home: DanmakuCachePage(cache: cache)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('128 MiB'));
    await tester.runAsync(() async {
      await tester.tap(find.text('128 MiB'));
      await Hive.box('setting').flush();
    });
    await tester.pumpAndSettle();
    expect(GStorage.getSetting(SettingsKeys.danmakuCacheMiB), 128);
    expect(cache.resizes, 1);
    await tester.ensureVisible(find.text('缓存弹幕服务数据'));
    await tester.runAsync(() async {
      await tester.tap(find.text('缓存弹幕服务数据'));
      await Hive.box('setting').flush();
    });
    await tester.pumpAndSettle();
    expect(GStorage.getSetting(SettingsKeys.danmakuCacheEnabled), isFalse);
    expect(GStorage.getSetting(SettingsKeys.recentVideoCacheEnabled), isFalse);
    expect(tester.takeException(), isNull);
  });
}
