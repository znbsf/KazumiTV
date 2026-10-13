import 'package:kazumi/pages/settings/storage_settings.dart';
import 'package:kazumi/services/storage/image_cache_service.dart';
import 'dart:io';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/settings/settings_page.dart';
import 'package:kazumi/pages/download/download_widgets.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('cache_focus_fixture_');
    PathProviderPlatform.instance = _Paths(temp.path);
    Hive.init(temp.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });
  testWidgets(
      'settings horizontal controls move left before exiting at left edge',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    addTearDown(() => TvMode.setEnabledForTesting(false));
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final first = FocusNode(debugLabel: 'first cache action');
    final second = FocusNode(debugLabel: 'second cache action');
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final disabled = FocusNode(debugLabel: 'disabled');
    final hidden = FocusNode(debugLabel: 'hidden');
    addTearDown(disabled.dispose);
    addTearDown(hidden.dispose);
    final module = createModule(register: (c) {
      c.route('/settings',
          child: (_, state) => SettingsPage(location: state.uri.path),
          children: (sub) {
            sub.route('/storage',
                child: (_, __) => Center(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                      TextButton(
                          focusNode: disabled,
                          onPressed: null,
                          child: const Text('disabled')),
                      Offstage(
                          offstage: true,
                          child: TextButton(
                              focusNode: hidden,
                              onPressed: () {},
                              child: const Text('hidden'))),
                      TextButton(
                          focusNode: first,
                          onPressed: () {},
                          child: const Text('Refresh fixture')),
                      TextButton(
                          focusNode: second,
                          onPressed: () {},
                          child: const Text('Cancel fixture')),
                    ])));
          });
    });
    await tester.pumpWidget(ModularApp(
        module: module,
        initialRoute: '/settings/storage',
        child: Builder(
            builder: (ctx) => MaterialApp.router(
                routerConfig: ModularApp.routerConfigOf(ctx)))));
    await tester.pumpAndSettle();
    second.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(first.hasPrimaryFocus, isTrue,
        reason: 'left must remain in the horizontal row');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        'TV settings category /settings/storage');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(first.hasPrimaryFocus, isTrue,
        reason: 'return should remember the pane control');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'storage confirmation arrows and Back/cancel preserve cache and return focus',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    addTearDown(() => TvMode.setEnabledForTesting(false));
    final cache = _CacheFixture();
    await tester
        .pumpWidget(MaterialApp(home: StorageSettingsPage(cache: cache)));
    await tester.pumpAndSettle();
    final tile = find.text('清除图片缓存');
    final origin = Focus.of(tester.element(tile));
    origin.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    final cancel = Focus.of(tester.element(find.text('取消')));
    final clear = Focus.of(tester.element(find.text('清除缓存')));
    expect(cancel.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(clear.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(cancel.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(cache.clears, 0);
    expect(origin.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(cache.clears, 0);
    expect(origin.hasPrimaryFocus, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'download episode horizontal actions reachable without activating row',
      (tester) async {
    final play = FocusNode(debugLabel: 'play fixture'),
        delete = FocusNode(debugLabel: 'delete fixture');
    addTearDown(play.dispose);
    addTearDown(delete.dispose);
    var played = 0, deleted = 0;
    final episode = DownloadEpisode(1, 'Episode fixture', 0,
        DownloadStatus.completed, 1, 1, 1, '', '', '', null, '', 0, '');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DownloadEpisodeTile(
                episode: episode,
                statusText: 'complete',
                onPlay: () => played++,
                actions: [
          IconButton(
              focusNode: play,
              onPressed: () => played++,
              icon: const Icon(Icons.play_arrow)),
          IconButton(
              focusNode: delete,
              onPressed: () => deleted++,
              icon: const Icon(Icons.delete)),
        ]))));
    delete.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(play.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(delete.hasPrimaryFocus, isTrue);
    expect(played, 0);
    expect(deleted, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _CacheFixture extends ImageCacheService {
  int clears = 0;
  @override
  Future<int> sizeInBytes() async => 42;
  @override
  Future<void> clear() async {
    clears++;
  }
}
