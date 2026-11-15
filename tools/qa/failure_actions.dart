// Isolated debug fixture: real production pages, native playback and actions.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
// ignore: depend_on_referenced_packages
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kazumi/core_module.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/tv_app_shell.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/pages/video/video_page.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/repositories/download_repository.dart';
import 'package:kazumi/request/clients/danmaku_client.dart';
import 'package:kazumi/services/danmaku/danmaku_cache_service.dart';
import 'package:kazumi/services/download/download_manager.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/player/audio_controller.dart';
import 'package:kazumi/services/player/cross_source_resume.dart';
import 'package:kazumi/services/player/recent_video_cache.dart';
import 'package:kazumi/services/player/recent_video_cache_service.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/video_source/services.dart';

const _base = String.fromEnvironment('FAILURE_ACTION_QA_BASE',
    defaultValue: 'http://127.0.0.1:18763');
late Directory _root;
late _FixtureCache _videoCache;
late DanmakuCacheService _apiCache;
late DanmakuClient _api;
String _scenario = 'cache';
int _requests = 0;

void _log(Map<String, Object?> data) =>
    debugPrint('FAILURE_ACTION_QA ${jsonEncode(data)}');

// Auth headers never leave this adapter. Only this local server is reachable.
class _LocalTransport implements HttpClientAdapter {
  final _client = HttpClient();
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.uri.host != 'api.dandanplay.net') {
      throw StateError('Fixture forbids external requests');
    }
    _requests++;
    _log({'event': 'request', 'scenario': _scenario, 'count': _requests});
    final request = await _client.getUrl(Uri.parse(_base)
        .replace(path: options.uri.path, queryParameters: {'mode': _scenario}));
    final response = await request.close().timeout(const Duration(seconds: 2),
        onTimeout: () {
      request.abort();
      throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
          message: 'Local server deadline');
    });
    final headers = <String, List<String>>{};
    response.headers.forEach((key, values) => headers[key] = values);
    return ResponseBody(response.map(Uint8List.fromList), response.statusCode,
        headers: headers);
  }

  @override
  void close({bool force = false}) => _client.close(force: force);
}

class _Lease extends RecentCacheLease {
  _Lease(Map<String, dynamic> data, this.cache)
      : super(data, RecentVideoCacheService());
  final RecentVideoCache cache;
  @override
  Future<void> release() => cache.release(data['token'] as String);
}

class _FixtureCache extends RecentVideoCacheService {
  _FixtureCache(this.cache);
  final RecentVideoCache cache;
  final id = RecentVideoCache.keyFor('failure-actions-synthetic-only');
  Future<void> seed() async {
    final directory =
        await Directory('${cache.root.path}/$id').create(recursive: true);
    const bytes = 'synthetic invalid MP4';
    await File('${directory.path}/s0.ts').writeAsString(bytes);
    await File('${directory.path}/entry.json').writeAsString(jsonEncode({
      'version': 1,
      'fingerprint': 'invalid-fixture',
      'playlist': '',
      'lengths': [utf8.encode(bytes).length],
      'metadata': {'position': 17, 'duration': 90},
      'accessed': DateTime.now().millisecondsSinceEpoch,
      'danmakuBytes': 0,
    }));
  }

  @override
  Future<RecentCacheLease?> find(String identity) async =>
      enabled && _scenario == 'cache' ? openOffline(id) : null;
  @override
  Future<RecentCacheLease?> openOffline(String id) async {
    final lease = await cache.openOffline(id);
    return lease == null ? null : _Lease(lease, cache);
  }

  @override
  Future<RecentCacheLease?> prepare(
          {required String identity,
          required String url,
          required Map<String, String> headers,
          required Map<String, dynamic> metadata,
          required bool hls,
          required bool adBlocker}) async =>
      null;
  @override
  Future<void> progress(String id, int position, int duration) =>
      cache.progress(id, position, duration);
  @override
  Future<(List<Never>, int)?> readDanmaku(String id) async => null;
}

class _Source implements WebViewVideoSourceService {
  @override
  Stream<String> get onLog => const Stream.empty();
  @override
  Future<VideoSource> resolve(String episodeUrl,
      {required bool useLegacyParser,
      int offset = 0,
      Duration timeout = const Duration(seconds: 15)}) async {
    _log({'event': 'resolve_origin', 'offset': offset});
    return VideoSource(
        url: '$_base/sample.mp4', offset: offset, type: VideoSourceType.online);
  }

  @override
  void cancel() {}
  @override
  Future<void> dispose() async {}
}

class _Video extends VideoPageController {
  _Video(HistoryController history, IDownloadRepository downloads,
      IDownloadManager manager)
      : super(history, downloads, manager,
            recentCache: _videoCache, videoSourceService: _Source());
  @override
  Future<bool> queryBangumiEpisodeCommentsByID(int id, int episode) async =>
      true;
}

class _Danmaku extends PlayerDanmakuController {
  _Danmaku(DownloadController downloads)
      : super(isLocalPlayback: () => false, downloadController: downloads);
  Future<DanmakuLoadResult> _load() async {
    try {
      await _api.get(
          'https://api.dandanplay.net/api/v2/comment/${_scenario == '429' ? 99001 : 99002}');
      return DanmakuLoadResult.success(danmakus: const [], bangumiID: 99000);
    } catch (error) {
      _log({'event': 'danmaku_failed', 'error': error.toString()});
      return DanmakuLoadResult.failed(bangumiID: 99000, error: error);
    }
  }

  @override
  Future<DanmakuLoadResult> fetchDanmaku(int id, String plugin, int episode,
          {int? downloadTaskNumber}) =>
      _load();
  @override
  Future<DanmakuLoadResult> fetchLatestDanmaku(int id, int episode) => _load();
}

class _Player extends PlayerController {
  _Player(ShaderAssetService shaders, DownloadController downloads,
      AudioController audio)
      : _fixtureDanmaku = _Danmaku(downloads),
        super(shaders, downloads, audio);
  final PlayerDanmakuController _fixtureDanmaku;
  @override
  PlayerDanmakuController get danmaku => _fixtureDanmaku;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode ||
      (await PackageInfo.fromPlatform()).packageName !=
          'com.znbsf.kazumi.fluttertv.remoteqa') {
    throw StateError('Isolated remoteqa debug entry only');
  }
  await TvMode.initialize();
  _root = await Directory(
          '${(await getApplicationSupportDirectory()).path}/failure_actions_qa')
      .create(recursive: true);
  await Hive.initFlutter('${_root.path}/hive');
  await GStorage.init();
  final state = File('${_root.path}/scenario.txt');
  if (await state.exists()) _scenario = await state.readAsString();
  await GStorage.putSetting(
      SettingsKeys.androidVideoRenderer, 'mediacodec_embed');
  await GStorage.putSetting(SettingsKeys.autoPlay, true);
  await GStorage.putSetting(SettingsKeys.autoPlayNext, false);
  await GStorage.putSetting(SettingsKeys.playResume, true);
  await GStorage.putSetting(SettingsKeys.defaultPlaySpeed, 1.0);
  await GStorage.putSetting(SettingsKeys.playerLogLevel, 3);
  _videoCache = _FixtureCache(RecentVideoCache(Directory('${_root.path}/video'),
      availableBytes: (_) async => 1 << 35));
  await _videoCache.seed();
  _apiCache = DanmakuCacheService(
      directory: () async => _root,
      enabled: () => true,
      privateMode: () => false,
      limitMiB: () => 64);
  _api = DanmakuClient.forTesting(
      dio: Dio()..httpClientAdapter = _LocalTransport(), cache: _apiCache);
  MediaKit.ensureInitialized();
  final module = createModule(register: (c) {
    c.module(coreModule);
    c.route('/', child: (_, __) => const _Home());
    c.route('/video/',
        provide: (s) => s
          ..add<VideoPageController>(_Video.new)
          ..add<PlayerController>(_Player.new),
        child: (context, state) {
          final player = context.read<PlayerController>();
          final video = context.read<VideoPageController>();
          return _Observe(
              player: player,
              video: video,
              child: VideoPage(
                  args: state.arguments as VideoPlaybackArgs,
                  playerController: player,
                  videoPageController: video,
                  historyController: inject<HistoryController>(),
                  downloadController: inject<DownloadController>()));
        });
  });
  runApp(ModularApp(
      module: module,
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [KazumiDialog.observer, rootRouteObserver],
      child: Builder(
          builder: (context) => MaterialApp.router(
              theme: ThemeData(brightness: Brightness.dark),
              scaffoldMessengerKey: rootScaffoldMessengerKey,
              routerConfig: ModularApp.routerConfigOf(context),
              builder: (_, child) => TvAppShell(child: child!)))));
}

class _Home extends StatefulWidget {
  const _Home();
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  Future<void> _open([String? scenario]) async {
    if (scenario != null) {
      _scenario = scenario;
      await File('${_root.path}/scenario.txt').writeAsString(scenario);
      await _apiCache.close();
      await GStorage.putSetting(SettingsKeys.recentVideoCacheEnabled,
          scenario == 'cache' || scenario == 'offline');
      await GStorage.putSetting(SettingsKeys.danmakuEnabledByDefault,
          scenario == '429' || scenario == 'timeout');
    }
    _log({
      'event': 'open',
      'scenario': _scenario,
      'cache': _videoCache.automaticEnabled,
      'danmakuDefault':
          GStorage.getSetting(SettingsKeys.danmakuEnabledByDefault),
      'requests': _requests
    });
    if (!mounted) return;
    final item = BangumiItem(
        id: 99000,
        type: 2,
        name: 'Controlled failure QA',
        nameCn: '故障按钮电视验收',
        summary: '',
        airDate: '',
        airWeekday: 0,
        rank: 0,
        images: {},
        tags: [],
        alias: [],
        ratingScore: 0,
        votes: 0,
        votesCount: List.filled(10, 0),
        info: '');
    final VideoPlaybackArgs args = _scenario == 'offline'
        ? OfflineVideoPlaybackArgs(
            bangumiItem: item,
            pluginName: 'Local fixture',
            episodeNumber: 1,
            road: 0,
            recentCacheId: _videoCache.id,
            downloadedEpisodes: [
                DownloadEpisode(1, '第1集', 0, DownloadStatus.completed, 100, 1,
                    1, '', '', '', null, '', 21, '')
              ])
        : OnlineVideoPlaybackArgs(
            bangumiItem: item,
            plugin:
                Plugin.fromJson({'name': 'Local fixture', 'baseURL': _base}),
            title: '故障按钮电视验收',
            src: '/fixture',
            allowHistoryResume: false,
            transfer: CrossSourceResume(
                bangumiId: 99000,
                pluginName: 'Local fixture',
                src: '/fixture',
                road: 0,
                episode: 1,
                episodePageUrl:
                    Uri.parse(_base).resolve('/episode1').toString(),
                offset: 17),
            roads: [
                Road(name: 'Local', data: ['/episode1'], identifier: ['第1集'])
              ]);
    await context.pushNamed('/video/', arguments: args);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
          body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
            '隔离测试 · 场景 $_scenario\n视频缓存：${_videoCache.automaticEnabled} · 默认弹幕：${GStorage.getSetting(SettingsKeys.danmakuEnabledByDefault)} · 本进程请求：$_requests'),
        const SizedBox(height: 20),
        FilledButton(
            autofocus: true,
            onPressed: () => _open('cache'),
            child: const Text('触发缓存播放失败')),
        FilledButton(
            onPressed: () => _open('offline'), child: const Text('触发离线缓存失败')),
        FilledButton(
            onPressed: () => _open('429'), child: const Text('触发弹幕429')),
        FilledButton(
            onPressed: () => _open('timeout'), child: const Text('触发弹幕超时')),
        FilledButton(onPressed: () => _open(), child: const Text('再次播放（保留设置）')),
      ])));
}

class _Observe extends StatefulWidget {
  const _Observe(
      {required this.player, required this.video, required this.child});
  final PlayerController player;
  final VideoPageController video;
  final Widget child;
  @override
  State<_Observe> createState() => _ObserveState();
}

class _ObserveState extends State<_Observe> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _log({
              'event': 'state',
              'scenario': _scenario,
              'positionMs':
                  widget.player.playback.playerPosition.inMilliseconds,
              'durationMs':
                  widget.player.playback.playerDuration.inMilliseconds,
              'playing': widget.player.playback.playing,
              'error': widget.video.errorMessage,
              'cache': _videoCache.automaticEnabled,
              'danmakuDefault':
                  GStorage.getSetting(SettingsKeys.danmakuEnabledByDefault),
              'danmakuOn': widget.player.danmaku.danmakuOn,
              'requests': _requests,
              'fixtureCacheExists':
                  File('${_videoCache.cache.root.path}/${_videoCache.id}/s0.ts')
                      .existsSync(),
            }));
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
