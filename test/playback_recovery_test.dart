import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/widget/media_error_widget.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'package:kazumi/pages/player/controller/player_playback_controller.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/pages/video/playback_recovery_shortcuts.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/repositories/download_repository.dart';
import 'package:kazumi/services/download/download_manager.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/player/source_switch.dart';
import 'package:kazumi/services/player/cross_source_resume.dart';
import 'package:kazumi/services/video_source/services.dart';
import 'package:kazumi/services/video_source/resolved_source_cache.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/tv_focus_fixtures.dart' show focusItem;

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _History implements HistoryController {
  final writes = <String>[];
  @override
  Future<void> updateHistory(
      PlaybackHistoryIdentity identity, Duration progress,
      {Duration duration = Duration.zero}) async {
    writes.add(identity.pluginName);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Downloads implements IDownloadRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _DownloadManager implements IDownloadManager {
  @override
  String? getLocalVideoPath(DownloadEpisode? episode) => '/fixture/video.mp4';
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Source implements WebViewVideoSourceService {
  final requests = <({String url, int offset})>[];
  Future<VideoSource> Function(String, int)? answer;
  int cancellations = 0;
  @override
  Stream<String> get onLog => const Stream.empty();
  @override
  Future<VideoSource> resolve(String episodeUrl,
      {required bool useLegacyParser,
      int offset = 0,
      Duration timeout = const Duration(seconds: 15)}) {
    requests.add((url: episodeUrl, offset: offset));
    return answer?.call(episodeUrl, offset) ??
        Future.value(VideoSource(
            url: 'https://media.example.test/video.mp4',
            offset: offset,
            type: VideoSourceType.online));
  }

  @override
  void cancel() => cancellations++;
  @override
  Future<void> dispose() async {}
}

class _Output implements VideoController {
  final frame = Completer<void>();
  @override
  Future<void> get waitUntilFirstFrameRendered => frame.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Playback implements PlayerPlaybackController {
  @override
  VideoController? videoController;
  @override
  bool playing = true;
  @override
  bool loading = true;
  @override
  Duration playerPosition = Duration.zero;
  @override
  Duration playerDuration = const Duration(minutes: 24);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Danmaku implements PlayerDanmakuController {
  @override
  Future<DanmakuLoadResult> fetchDanmaku(
          int id, String plugin, int episode) async =>
      DanmakuLoadResult.success(danmakus: const [], bangumiID: id);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Player implements PlayerController {
  @override
  final _Playback playback = _Playback();
  @override
  final _Danmaku danmaku = _Danmaku();
  final initializations = <PlaybackInitParams>[];
  Future<bool> Function(PlaybackInitParams)? initialize;
  int stops = 0;
  @override
  Future<bool> init(PlaybackInitParams params) async {
    initializations.add(params);
    final result = await (initialize?.call(params) ?? Future.value(true));
    playback.loading = false;
    return result;
  }

  @override
  Future<void> pause({bool enableSync = true}) async {
    playback.playing = false;
  }

  @override
  Future<void> stop() async {
    stops++;
    playback.loading = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late _Source source;
  late _Player player;
  late VideoPageController controller;
  late _History history;
  setUpAll(() async {
    temporary = await Directory.systemTemp.createTemp('kazumi_recovery_');
    PathProviderPlatform.instance = _Paths(temporary.path);
    Hive.init(temporary.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    await temporary.delete(recursive: true);
  });
  setUp(() {
    history = _History();
    source = _Source();
    player = _Player();
    controller = VideoPageController(history, _Downloads(), _DownloadManager(),
        videoSourceService: source, resolvedSourceCache: ResolvedSourceCache());
    controller.applyPlaybackArgs(OnlineVideoPlaybackArgs(
      bangumiItem: focusItem(1),
      plugin: Plugin.fromJson(
          {'name': 'fixture', 'baseURL': 'https://example.test'}),
      title: 'Recovery fixture',
      src: '/subject',
      roads: [
        Road(name: 'A', data: ['/a/1', '/a/2'], identifier: ['第1集', '第2集']),
        Road(
            name: 'B reversed',
            data: ['/b/2', '/b/1'],
            identifier: ['第2集', '第1集']),
        Road(
            name: 'Ambiguous',
            data: ['/c/2a', '/c/2b'],
            identifier: ['第2集', '第2集']),
      ],
    ));
  });
  tearDown(() {
    controller.dispose();
    TvMode.setEnabledForTesting(false);
  });

  PreparedSourceSwitch candidate() => PreparedSourceSwitch(
        OnlineVideoPlaybackArgs(
          bangumiItem: focusItem(1),
          plugin:
              Plugin.fromJson({'name': 'new', 'baseURL': 'https://new.test'}),
          title: 'New source',
          src: '/new',
          roads: [
            Road(
                name: 'reversed',
                data: ['/two', '/one'],
                identifier: ['第2集', '第1集'])
          ],
          allowHistoryResume: false,
          transfer: const CrossSourceResume(
              bangumiId: 1,
              pluginName: 'new',
              src: '/new',
              road: 0,
              episode: 1,
              episodePageUrl: 'https://new.test/two',
              offset: 42),
        ),
        const VideoSource(
            url: 'https://new.test/video.mp4',
            offset: 42,
            type: VideoSourceType.online),
      );

  test(
      'rendered episode falls back after parser timeout once with same headers',
      () async {
    final output = _Output();
    player.playback.videoController = output;
    await controller.changeEpisode(1, playerController: player);
    final original = player.initializations.single;
    output.frame.complete();
    await Future<void>.delayed(Duration.zero);
    source.answer = (_, __) =>
        Future.error(const VideoSourceTimeoutException(Duration(seconds: 15)));
    player.playback.playerPosition = const Duration(seconds: 99);
    await controller.retryCurrentEpisode(playerController: player);
    expect(player.initializations, hasLength(2));
    expect(player.initializations.last.videoUrl, original.videoUrl);
    expect(player.initializations.last.httpHeaders, original.httpHeaders);
    expect(player.initializations.last.offset, 99);
    expect(controller.errorMessage, isNull);
    await controller.retryCurrentEpisode(playerController: player);
    expect(player.initializations, hasLength(2));
    expect(controller.errorMessage, contains('解析超时'));
  });

  test('rendered first episode cannot be reused for another episode', () async {
    final output = _Output();
    player.playback.videoController = output;
    await controller.changeEpisode(1, playerController: player);
    output.frame.complete();
    await Future<void>.delayed(Duration.zero);
    source.answer = (_, __) =>
        Future.error(const VideoSourceTimeoutException(Duration(seconds: 15)));
    await controller.changeEpisode(2, playerController: player);
    expect(player.initializations, hasLength(1));
    expect(controller.errorMessage, contains('解析超时'));
  });

  test('native failure invalidates previously confirmed address', () async {
    final output = _Output();
    player.playback.videoController = output;
    await controller.changeEpisode(1, playerController: player);
    output.frame.complete();
    await Future<void>.delayed(Duration.zero);
    player.initializations.single.onPlaybackError!('network failed');
    source.answer = (_, __) =>
        Future.error(const VideoSourceTimeoutException(Duration(seconds: 15)));
    await controller.retryCurrentEpisode(playerController: player);
    expect(player.initializations, hasLength(1));
    expect(controller.errorMessage, contains('解析超时'));
  });

  test('prepared commit keeps selected headers after selected plugin changes',
      () async {
    await controller.changeEpisode(2, playerController: player);
    final before = candidate();
    final headers = {
      'user-agent': 'UA-used-by-selected-parser',
      'referer': 'https://new.test/parse-time/'
    };
    final prepared =
        PreparedSourceSwitch.withHeaders(before.args, before.source, headers);
    headers['user-agent'] = 'mutated-caller';
    before.args.plugin.userAgent = 'regenerated-selected-UA';
    before.args.plugin.referer = 'https://new.test/changed/';
    expect(
        await controller.switchSource(prepared,
            expectedRevision: controller.playbackRevision,
            playerController: player),
        isTrue);
    expect(player.initializations.last.httpHeaders, {
      'user-agent': 'UA-used-by-selected-parser',
      'referer': 'https://new.test/parse-time/'
    });
    expect(player.initializations.last.referer, 'https://new.test/parse-time/');
    expect(source.requests, hasLength(1));
  });

  for (final failure in ['false', 'throw']) {
    test('native $failure rollback reuses original actual headers and pause',
        () async {
      await controller.changeEpisode(2, playerController: player);
      final original = player.initializations.single;
      final originalHeaders = Map<String, String>.from(original.httpHeaders);
      controller.currentPlugin.userAgent = 'must-not-regenerate-original';
      controller.currentPlugin.referer = 'https://changed-original.test/';
      player.playback.playerPosition = const Duration(seconds: 81);
      player.playback.playing = false;
      player.initialize = (params) async {
        if (params.pluginName == 'new') {
          if (failure == 'throw') throw StateError('native target rejected');
          return false;
        }
        return true;
      };
      final target = candidate();
      final prepared = PreparedSourceSwitch.withHeaders(
          target.args, target.source, {
        'user-agent': 'selected-exact',
        'referer': 'https://selected.test/'
      });
      expect(
          await controller.switchSource(prepared,
              expectedRevision: controller.playbackRevision,
              playerController: player),
          isFalse);
      expect(player.initializations[1].httpHeaders['user-agent'],
          'selected-exact');
      expect(player.initializations.last.httpHeaders, originalHeaders);
      expect(player.initializations.last.referer, original.referer);
      expect(player.initializations.last.offset, 81);
      expect(player.playback.playing, isFalse);
      expect(source.requests, hasLength(1));
      expect(controller.currentPlugin.name, 'fixture');
    });
  }

  test('cached playback actual headers survive failed source rollback',
      () async {
    final output = _Output();
    player.playback.videoController = output;
    await controller.changeEpisode(1, playerController: player);
    final originalHeaders = player.initializations.single.httpHeaders;
    output.frame.complete();
    await Future<void>.delayed(Duration.zero);
    source.answer = (_, __) =>
        Future.error(const VideoSourceTimeoutException(Duration(seconds: 15)));
    await controller.retryCurrentEpisode(playerController: player);
    expect(player.initializations.last.httpHeaders, originalHeaders);
    player.initialize = (params) async => params.pluginName != 'new';
    expect(
        await controller.switchSource(candidate(),
            expectedRevision: controller.playbackRevision,
            playerController: player),
        isFalse);
    expect(player.initializations.last.httpHeaders, originalHeaders);
  });

  test('source switch commits pre-resolved media without a second parse',
      () async {
    await controller.changeEpisode(2, playerController: player);
    final revision = controller.playbackRevision;
    expect(
        await controller.switchSource(candidate(),
            expectedRevision: revision, playerController: player),
        isTrue);
    expect(source.requests, hasLength(1));
    expect(controller.currentPlugin.name, 'new');
    expect(controller.playbackEpisode.episode, 1);
    expect(controller.currentHistoryIdentity!.episodeTitle, '第2集');
    expect(player.initializations.last.offset, 42);
  });

  test(
      'failed native initialization restores original source, position and pause',
      () async {
    await controller.changeEpisode(2, playerController: player);
    player.playback.playerPosition = const Duration(seconds: 81);
    player.playback.playing = false;
    player.initialize = (params) async => params.pluginName != 'new';
    expect(
        await controller.switchSource(candidate(),
            expectedRevision: controller.playbackRevision,
            playerController: player),
        isFalse);
    expect(controller.currentPlugin.name, 'fixture');
    expect(controller.src, '/subject');
    expect(controller.playingEpisode!.episode, 2);
    expect(controller.currentHistoryIdentity!.pluginName, 'fixture');
    expect(player.initializations.last.offset, 81);
    expect(player.playback.playing, isFalse);
    expect(source.requests, hasLength(1));
  });

  test('failed target cannot write history during init or after rollback',
      () async {
    TvMode.setEnabledForTesting(true);
    await controller.changeEpisode(2, playerController: player);
    player.initialize = (params) async {
      await params.onHistoryProgress
          ?.call(const Duration(seconds: 42), const Duration(minutes: 24));
      return params.pluginName != 'new';
    };
    expect(
        await controller.switchSource(candidate(),
            expectedRevision: controller.playbackRevision,
            playerController: player),
        isFalse);
    final failedParams = player.initializations
        .firstWhere((params) => params.pluginName == 'new');
    await failedParams.onHistoryProgress!
        .call(const Duration(seconds: 43), const Duration(minutes: 24));
    expect(history.writes, isEmpty);
    await player.initializations.last.onHistoryProgress!
        .call(const Duration(seconds: 44), const Duration(minutes: 24));
    expect(history.writes, ['fixture']);
  });

  test('switch failure from error screen restores original retry identity',
      () async {
    source.answer =
        (_, __) => Future.error(const VideoSourceNotFoundException());
    await controller.changeEpisode(2, offset: 17, playerController: player);
    final oldError = controller.errorMessage;
    player.initialize = (_) async => false;
    expect(
        await controller.switchSource(candidate(),
            expectedRevision: controller.playbackRevision,
            playerController: player),
        isFalse);
    expect(controller.currentPlugin.name, 'fixture');
    expect(controller.selectedEpisode.episode, 2);
    expect(controller.errorMessage, oldError);
    expect(controller.recoveryOffset(player), 17);
  });

  test('duplicate and stale source commits cannot replace newer playback',
      () async {
    await controller.changeEpisode(2, playerController: player);
    final oldRevision = controller.playbackRevision;
    final pending = Completer<bool>();
    player.initialize = (params) =>
        params.pluginName == 'new' ? pending.future : Future.value(true);
    final switching = controller.switchSource(candidate(),
        expectedRevision: oldRevision, playerController: player);
    await Future<void>.delayed(Duration.zero);
    expect(
        await controller.switchSource(candidate(),
            expectedRevision: oldRevision, playerController: player),
        isFalse);
    player.initialize = (_) async => true;
    await controller.changeEpisode(2, playerController: player);
    pending.complete(false);
    expect(await switching, isFalse);
    expect(controller.currentPlugin.name, 'new');
    expect(controller.selectedEpisode.episode, 2);
    expect(
        await controller.switchSource(candidate(),
            expectedRevision: oldRevision, playerController: player),
        isFalse);
  });

  test('dispose rejects a late source switch without restoring a dead route',
      () async {
    await controller.changeEpisode(2, playerController: player);
    final pending = Completer<bool>();
    player.initialize = (_) => pending.future;
    final switching = controller.switchSource(candidate(),
        expectedRevision: controller.playbackRevision,
        playerController: player);
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    pending.complete(false);
    expect(await switching, isFalse);
    expect(player.initializations, hasLength(2));
  });

  for (final failure in [
    const VideoSourceTimeoutException(Duration(seconds: 15)),
    const VideoSourceNotFoundException(),
  ]) {
    test('failed current episode retries its own offset after $failure',
        () async {
      source.answer = (_, __) => Future.error(failure);
      await controller.changeEpisode(2, offset: 18, playerController: player);
      expect(controller.errorMessage, isNotNull);
      expect(controller.loading, isFalse);
      source.answer = null;
      await controller.selectEpisode(2, road: 0, playerController: player);
      expect(source.requests.map((e) => e.offset), [18, 18]);
      expect(player.initializations.single.episode, 2);
      expect(player.initializations.single.offset, 18);
      expect(controller.errorMessage, isNull);
      expect(controller.playingEpisode,
          const VideoEpisodeSelection(episode: 2, road: 0));
      await controller.selectEpisode(2, road: 0, playerController: player);
      expect(source.requests, hasLength(2));
    });
  }

  test(
      'media initialization failure is visible and retry preserves the request',
      () async {
    player.initialize = (_) async => false;
    await controller.changeEpisode(2, offset: 42, playerController: player);
    expect(controller.loading, isFalse);
    expect(controller.errorMessage, contains('播放器加载失败'));
    expect(controller.playingEpisode, isNull);
    player.initialize = null;
    await controller.retryCurrentEpisode(playerController: player);
    expect(player.initializations.last.offset, 42);
    expect(controller.errorMessage, isNull);
  });

  test(
      'failed road transfer matches episode identity and refuses ambiguous matches',
      () async {
    source.answer =
        (_, __) => Future.error(const VideoSourceNotFoundException());
    await controller.changeEpisode(2, offset: 53, playerController: player);
    expect(controller.recoveryOnRoad(1, player),
        (episode: 1, road: 1, offset: 53));
    expect(controller.recoveryOnRoad(2, player), isNull);
    final target = controller.recoveryOnRoad(1, player)!;
    source.answer = null;
    await controller.changeEpisode(target.episode,
        currentRoad: target.road,
        offset: target.offset,
        playerController: player);
    expect(source.requests.last, (url: 'https://example.test/b/2', offset: 53));
  });

  test(
      'refresh captures current progress but a different failed episode never borrows it',
      () async {
    await controller.changeEpisode(1, offset: 18, playerController: player);
    player.playback.playerPosition = const Duration(seconds: 91);
    await controller.retryCurrentEpisode(playerController: player);
    expect(player.initializations.last.offset, 91);
    source.answer =
        (_, __) => Future.error(const VideoSourceNotFoundException());
    await controller.changeEpisode(2, playerController: player);
    expect(controller.recoveryOffset(player), 0);
    source.answer = null;
    await controller.retryCurrentEpisode(playerController: player);
    expect(player.initializations.last.episode, 2);
    expect(player.initializations.last.offset, 0);
  });

  test('cancel retires the old request; late completion cannot replace retry',
      () async {
    final pending = Completer<VideoSource>();
    source.answer = (_, __) => pending.future;
    final old =
        controller.changeEpisode(2, offset: 71, playerController: player);
    await Future<void>.delayed(Duration.zero);
    await controller.selectEpisode(2, road: 0, playerController: player);
    expect(source.requests, hasLength(1));
    final cancellations = source.cancellations;
    await controller.cancelEpisodeLoad(playerController: player);
    expect(source.cancellations, cancellations + 1);
    expect(controller.errorMessage, contains('已取消加载'));
    source.answer = null;
    await controller.retryCurrentEpisode(playerController: player);
    pending.complete(const VideoSource(
        url: 'https://old.example.test/old.mp4',
        offset: 71,
        type: VideoSourceType.online));
    await old;
    expect(player.initializations, hasLength(1));
    expect(player.initializations.single.offset, 71);
    expect(controller.errorMessage, isNull);
  });

  test(
      'timeout retry can be cancelled and retried without late-error pollution',
      () async {
    source.answer = (_, __) =>
        Future.error(const VideoSourceTimeoutException(Duration(seconds: 15)));
    await controller.changeEpisode(2, offset: 71, playerController: player);
    expect(controller.errorMessage, isNotNull);
    expect(controller.loading, isFalse);

    final pending = Completer<VideoSource>();
    source.answer = (_, __) => pending.future;
    final retry = controller.retryCurrentEpisode(playerController: player);
    await Future<void>.delayed(Duration.zero);
    expect(controller.loading, isTrue);
    await controller.cancelEpisodeLoad(playerController: player);
    expect(controller.loading, isFalse);
    expect(controller.errorMessage, contains('已取消加载'));

    source.answer = null;
    await controller.retryCurrentEpisode(playerController: player);
    pending.completeError(const VideoSourceNotFoundException());
    await retry;
    expect(source.requests.map((request) => request.offset), [71, 71, 71]);
    expect(player.initializations, hasLength(1));
    expect(player.initializations.single.episode, 2);
    expect(player.initializations.single.offset, 71);
    expect(controller.errorMessage, isNull);
    expect(controller.playingEpisode,
        const VideoEpisodeSelection(episode: 2, road: 0));
  });

  test('repeated source commits retain history identity and ignore old errors',
      () async {
    TvMode.setEnabledForTesting(true);
    await controller.changeEpisode(2, playerController: player);
    final original = player.initializations.single;
    for (var attempt = 0; attempt < 3; attempt++) {
      expect(
          await controller.switchSource(candidate(),
              expectedRevision: controller.playbackRevision,
              playerController: player),
          isTrue);
    }
    expect(source.requests, hasLength(1));
    for (final old in player.initializations.take(3)) {
      await old.onHistoryProgress!
          .call(const Duration(seconds: 99), const Duration(minutes: 24));
    }
    // A retired native session may still flush its last real progress. Its
    // captured identity must not be rewritten as the current source.
    expect(history.writes, ['fixture', 'new', 'new']);
    final current = player.initializations.last;
    await current.onHistoryProgress!
        .call(const Duration(seconds: 43), const Duration(minutes: 24));
    expect(history.writes, ['fixture', 'new', 'new', 'new']);
    controller.dispose();
    original.onPlaybackError!('late original failure after exit');
    await current.onHistoryProgress!
        .call(const Duration(seconds: 44), const Duration(minutes: 24));
    expect(history.writes, ['fixture', 'new', 'new', 'new', 'new']);
    expect(controller.errorMessage, isNull);
  });

  test('late failed initialization cannot overwrite a newer successful episode',
      () async {
    final pending = Completer<bool>();
    player.initialize =
        (params) => params.episode == 1 ? pending.future : Future.value(true);
    final old = controller.changeEpisode(1, playerController: player);
    await Future<void>.delayed(Duration.zero);
    player.initialize = (_) async => true;
    await controller.changeEpisode(2, playerController: player);
    pending.complete(false);
    await old;
    expect(controller.errorMessage, isNull);
    expect(controller.playingEpisode,
        const VideoEpisodeSelection(episode: 2, road: 0));
  });

  test('offline media failure also offers retry with the requested offset',
      () async {
    controller.applyPlaybackArgs(OfflineVideoPlaybackArgs(
      bangumiItem: focusItem(1),
      pluginName: 'fixture',
      episodeNumber: 7,
      road: 3,
      downloadedEpisodes: [
        DownloadEpisode(
            7,
            '第7集',
            3,
            DownloadStatus.completed,
            100,
            1,
            1,
            '/fixture/video.mp4',
            '/fixture',
            '',
            DateTime(2026),
            '',
            1,
            '/ep/7')
      ],
    ));
    player.initialize = (_) async => false;
    await controller.changeEpisode(1, offset: 62, playerController: player);
    expect(controller.errorMessage, contains('本地视频加载失败'));
    player.initialize = null;
    await controller.retryCurrentEpisode(playerController: player);
    expect(player.initializations.last.offset, 62);
    expect(player.initializations.last.danmakuEpisodeNumber, 7);
    expect(controller.errorMessage, isNull);
  });

  test(
      'asynchronous open failure preserves resume before duration arrives and ignores old errors',
      () async {
    await controller.changeEpisode(2, offset: 42, playerController: player);
    final failedPlayer = player.initializations.single;
    player.playback.playerDuration = Duration.zero;
    failedPlayer.onPlaybackError!('加载失败, 请尝试更换其他视频来源');
    expect(controller.errorMessage, contains('播放器加载失败'));
    expect(controller.playingEpisode, isNull);
    await controller.retryCurrentEpisode(playerController: player);
    expect(player.initializations.last.offset, 42);
    failedPlayer.onPlaybackError!('late old media error');
    expect(controller.errorMessage, isNull);
    expect(controller.playingEpisode,
        const VideoEpisodeSelection(episode: 2, road: 0));
  });

  test('media failure after progress preserves actual position when retrying',
      () async {
    await controller.changeEpisode(1, offset: 18, playerController: player);
    player.playback.playerPosition = const Duration(seconds: 91);
    player.initializations.single.onPlaybackError!('无法识别媒体格式');
    await controller.retryCurrentEpisode(playerController: player);
    expect(player.initializations.last.offset, 91);
  });

  test(
      'cancel during initialization allows a different episode without old offset or errors',
      () async {
    final pending = Completer<bool>();
    player.initialize =
        (params) => params.episode == 1 ? pending.future : Future.value(true);
    final old =
        controller.changeEpisode(1, offset: 71, playerController: player);
    await Future<void>.delayed(Duration.zero);
    final oldParams = player.initializations.single;
    await controller.cancelEpisodeLoad(playerController: player);
    await controller.selectEpisode(2, road: 0, playerController: player);
    oldParams.onPlaybackError!('old open failed');
    pending.complete(false);
    await old;
    expect(player.initializations.last.offset, 0);
    expect(controller.errorMessage, isNull);
    expect(controller.playingEpisode,
        const VideoEpisodeSelection(episode: 2, road: 0));
  });

  for (final railOpen in [true, false]) {
    testWidgets(
        'error surface Back works with rail open=$railOpen and does not repeat',
        (tester) async {
      final playerFocus = FocusNode();
      final railFocus = FocusNode();
      addTearDown(playerFocus.dispose);
      addTearDown(railFocus.dispose);
      var backCalls = 0;
      await tester.pumpWidget(MaterialApp(
          home: PlaybackRecoveryShortcuts(
        enabled: true,
        onBack: () => backCalls++,
        child: Stack(children: [
          Focus(
              descendantsAreFocusable: !railOpen,
              child: Focus(focusNode: playerFocus, child: const SizedBox())),
          if (railOpen) Focus(focusNode: railFocus, child: const SizedBox()),
        ]),
      )));
      (railOpen ? railFocus : playerFocus).requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      expect(backCalls, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.goBack,
          physicalKey: PhysicalKeyboardKey.escape);
      expect(backCalls, 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'media failure exposes keyboard-activated retry and source selection',
      (tester) async {
    var retries = 0, selections = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MediaErrorWidget(
      title: '暂时无法播放',
      errMsg: '视频解析超时，请重试',
      icon: Icons.videocam_off,
      onRetry: () => retries++,
      retryText: '重试当前集',
      actions: [
        StateActionButton.tonal(
            onPressed: () => selections++, text: '选集 / 换线路'),
      ],
    ))));
    final retry = find.widgetWithText(FilledButton, '重试当前集');
    Focus.of(tester.element(
            find.descendant(of: retry, matching: find.byType(Text)).first))
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(retries, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(selections, 1);
    expect(tester.takeException(), isNull);
  });
}
