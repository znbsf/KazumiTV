import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/pages/settings/recent_video_cache_page.dart';
import 'package:kazumi/services/player/recent_video_cache_service.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Cache extends RecentVideoCacheService {
  bool automatic = false;
  int capacity = 2;
  @override
  bool get automaticEnabled => automatic;
  @override
  int get limitGiB => capacity;
  @override
  Future<void> setEnabled(bool value) async {
    automatic = value;
  }

  @override
  Future<void> setLimitGiB(int value) async {
    capacity = value;
  }

  final deleted = <String?>[];
  final entries = <Map<String, dynamic>>[
    {
      'id': 'one',
      'metadata': {'title': '番剧甲', 'episodeTitle': '第1集'},
      'bytes': 10 * 1024 * 1024,
      'complete': true,
      'active': false,
      'saved': 2,
      'total': 2
    },
    {
      'id': 'two',
      'metadata': {'title': '番剧乙', 'episodeTitle': '第2集'},
      'bytes': 5 * 1024 * 1024,
      'complete': false,
      'active': true,
      'saved': 1,
      'total': 2
    },
  ];
  @override
  Future<List<Map<String, dynamic>>> list() async => List.of(entries);
  @override
  Future<void> clear({String? id}) async {
    deleted.add(id);
    entries.removeWhere((e) => e['id'] == id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('recent_cache_ui_');
    PathProviderPlatform.instance = _Paths(temp.path);
    Hive.init(temp.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });
  testWidgets(
      'TV page exposes complete/partial states and confirms per-episode deletion',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    addTearDown(() => TvMode.setEnabledForTesting(false));
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cache = _Cache();
    await tester
        .pumpWidget(MaterialApp(home: RecentVideoCachePage(service: cache)));
    await tester.pumpAndSettle();
    expect(find.textContaining('可离线播放'), findsOneWidget);
    expect(find.textContaining('部分缓存 1/2'), findsOneWidget);
    final deletes = find.widgetWithText(TextButton, '删除这一集');
    expect(tester.widget<TextButton>(deletes.at(1)).onPressed, isNull);
    await tester.ensureVisible(deletes.first);
    await tester.tap(deletes.first);
    await tester.pumpAndSettle();
    expect(find.text('删除这一集的缓存？'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(cache.deleted, isEmpty);
    await tester.tap(deletes.first);
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(TextButton, '删除');
    Focus.of(tester.element(confirm), scopeOk: true);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(cache.deleted, ['one']);
    expect(find.text('番剧甲 · 第1集'), findsNothing);
    expect(find.text('番剧乙 · 第2集'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('TV remote can change capacity and toggle opt-in',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    addTearDown(() => TvMode.setEnabledForTesting(false));
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cache = _Cache();
    await tester
        .pumpWidget(MaterialApp(home: RecentVideoCachePage(service: cache)));
    await tester.pumpAndSettle();
    final dropdown = find.byType(DropdownButton<int>);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(cache.capacity, 4);
    await tester.tap(find.text('自动缓存观看视频（实验功能）'));
    await tester.pumpAndSettle();
    expect(cache.automatic, true);
    expect(tester.takeException(), isNull);
  });
  test('private mode suppresses automatic cache even with the switch enabled',
      () async {
    await GStorage.putSetting(SettingsKeys.recentVideoCacheEnabled, true);
    await GStorage.putSetting(SettingsKeys.privateMode, true);
    expect(RecentVideoCacheService().enabled, false);
    await GStorage.putSetting(SettingsKeys.privateMode, false);
    expect(RecentVideoCacheService().enabled, true);
  });
}
