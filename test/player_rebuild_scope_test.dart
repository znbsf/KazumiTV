import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:mobx/mobx.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/pages/my/my_controller.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/player/player_item.dart';
import 'package:kazumi/pages/player/player_item_panel.dart';
import 'package:kazumi/pages/video/video_page.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/repositories/download_repository.dart';
import 'package:kazumi/services/download/download_manager.dart';
import 'package:kazumi/services/player/audio_controller.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/video_source/services.dart';
import 'support/tv_focus_fixtures.dart';

class Paths extends PathProviderPlatform {
  Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class Downloads implements DownloadController {
  @override
  DownloadRecord? getRecordSnapshot(String key) => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Repo implements IDownloadRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Manager implements IDownloadManager {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Shader implements ShaderAssetService {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class My implements MyController {
  @override
  bool isDanmakuBlocked(String? text) => false;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class HistoryRepo extends FocusHistoryRepository {
  HistoryRepo() : super(count: 0);
  @override
  History? getHistory(String adapterName, BangumiItem item,
          {String entryKind = HistoryEntryKind.online}) =>
      null;
}

class Audio extends AudioController {
  @override
  Future<void> bindCallbacks(
      {required AudioCallback onPlay,
      required AudioCallback onPause,
      required AudioCallback onSkipToNext,
      required AudioCallback onSkipToPrevious,
      required AudioSeekCallback onSeek,
      required String? artworkUrl}) async {}
}

class VideoState extends VideoPageController {
  VideoState(HistoryController history) : super(history, Repo(), Manager());
  @override
  bool get loading => false;
  @override
  void isDesktopFullscreen() {}
  @override
  Future<void> changeEpisode(int episode,
      {int currentRoad = 0,
      int offset = 0,
      required PlayerController playerController,
      VideoSource? preparedSource,
      Map<String, String>? preparedHeaders}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('kazumi-rebuild-review-');
    PathProviderPlatform.instance = Paths(temp.path);
    Hive.init(temp.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });
  for (final desktop in [false, true]) {
    testWidgets(
        'production player rebuild and state retention desktop=$desktop',
        (tester) async {
      TvMode.setEnabledForTesting(!desktop);
      addTearDown(() => TvMode.setEnabledForTesting(false));
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final downloads = Downloads();
      final history = HistoryController(HistoryRepo());
      final video = VideoState(history);
      if (desktop) {
        runInAction(() => video.isFullscreen = true);
      }
      final player = PlayerController(Shader(), downloads, Audio());
      player.bangumiId = 1;
      player.currentEpisode = 1;
      player.currentRoad = 0;
      player.currentDanmakuEpisodeNumber = 1;
      player.referer = '';
      runInAction(() {
        player.playback.loading = false;
        player.playback.isBuffering = false;
      });
      final args = OnlineVideoPlaybackArgs(
          bangumiItem: focusItem(1),
          plugin: Plugin.fromJson(
              {'name': 'test', 'baseURL': 'https://example.invalid'}),
          title: 'Review',
          src: 'https://example.invalid/series',
          allowHistoryResume: false,
          roads: [
            Road(name: 'test', data: ['/ep1', '/ep2'], identifier: ['1', '2'])
          ]);
      final module = createModule(register: (c) {
        c.addInstance<MyController>(My());
        c.addInstance<CollectController>(FocusCollectController());
        c.addInstance<DownloadController>(downloads);
        c.addInstance<HistoryController>(history);
        c.route('/',
            child: (_, __) => VideoPage(
                args: args,
                playerController: player,
                videoPageController: video,
                historyController: history,
                downloadController: downloads));
      });
      await tester.pumpWidget(ModularApp(
          module: module,
          initialRoute: '/',
          child: Builder(
              builder: (context) => MaterialApp.router(
                  routerConfig: ModularApp.routerConfigOf(context)))));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      final itemFinder = find.byType(PlayerItem);
      final panelFinder = find.byType(PlayerItemPanel);
      expect(itemFinder, findsOneWidget);
      expect(panelFinder, findsOneWidget);
      final itemState = tester.state(itemFinder);
      final panelState = tester.state(panelFinder);
      final itemElement = tester.element(itemFinder);
      Element? rootObserver;
      itemElement.visitChildElements((e) => rootObserver = e);
      var itemBuilds = 0, panelBuilds = 0, rootBuilds = 0;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        if (element.widget is PlayerItem) itemBuilds++;
        if (element.widget is PlayerItemPanel) panelBuilds++;
        if (identical(element, rootObserver)) rootBuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      Future<void> step() async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
      }

      void report(String scenario) {
        debugPrint(
            'REBUILD $scenario item=$itemBuilds root=$rootBuilds panel=$panelBuilds');
        expect(tester.state(itemFinder), same(itemState));
        expect(tester.state(panelFinder), same(panelState));
        expect(itemBuilds, 0);
        expect(rootBuilds, 0);
        expect(panelBuilds, 0);
        itemBuilds = panelBuilds = rootBuilds = 0;
      }

      for (var i = 0; i < 6; i++) {
        tester.widget<PlayerItem>(itemFinder).toggleMenu();
        await step();
        if (!desktop && video.showTabBody) {
          expect(tester.widget<PlayerItem>(itemFinder).keyboardFocus.hasFocus,
              isFalse);
        }
      }
      report('rail-six-toggles');
      // Close the rail before checking player-owned focus.
      if (video.showTabBody) {
        tester.widget<PlayerItem>(itemFinder).toggleMenu();
        await step();
      }
      final focus = tester.widget<PlayerItem>(itemFinder).keyboardFocus;
      focus.requestFocus();
      await step();
      itemBuilds = panelBuilds = rootBuilds = 0;
      final idleSpinners =
          find.byType(CircularProgressIndicator).evaluate().length;
      for (var i = 0; i < 10; i++) {
        runInAction(
            () => player.playback.isBuffering = !player.playback.isBuffering);
        await step();
        expect(focus.hasFocus, isTrue);
        expect(find.byType(CircularProgressIndicator).evaluate().length,
            idleSpinners + (player.playback.isBuffering ? 1 : 0));
      }
      report('buffer-ten-flips');
      for (var i = 0; i < 10; i++) {
        runInAction(() => player.panel.showVideoController =
            !player.panel.showVideoController);
        await step();
      }
      report('controls-ten-flips');
      expect(tester.takeException(), isNull);
      debugOnRebuildDirtyWidget = null;
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
