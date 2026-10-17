// Debug-only lifecycle probe. Uses the real VideoPage, PlayerController and native output.
// Server mode controls real media responses; no injected decoder errors.
import 'dart:async';
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
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'package:kazumi/services/player/audio_controller.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/pages/video/video_page.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/repositories/download_repository.dart';
import 'package:kazumi/services/download/download_manager.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/video_source/services.dart';

const _base = String.fromEnvironment('LIFECYCLE_QA_BASE',
    defaultValue: 'http://10.0.2.2:18743');

const _normal = String.fromEnvironment('LIFECYCLE_QA_NORMAL',
    defaultValue: '$_base/health.mp4');
const _controlled = String.fromEnvironment('LIFECYCLE_QA_CONTROLLED',
    defaultValue: '$_base/sample.mkv');
String _selectedMedia = _normal;

class _Source implements WebViewVideoSourceService {
  @override
  Stream<String> get onLog => const Stream.empty();
  @override
  Future<VideoSource> resolve(String episodeUrl,
      {required bool useLegacyParser,
      int offset = 0,
      Duration timeout = const Duration(seconds: 15)}) async {
    debugPrint('LIFECYCLE_QA resolve local fixture');
    return VideoSource(
        url: _selectedMedia, offset: 0, type: VideoSourceType.online);
  }

  @override
  void cancel() {}
  @override
  Future<void> dispose() async {}
}

// Avoid unrelated public comment requests; playback and UI remain production.
class _Video extends VideoPageController {
  _Video(HistoryController history, IDownloadRepository downloads,
      IDownloadManager manager)
      : super(history, downloads, manager, videoSourceService: _Source());
  @override
  Future<bool> queryBangumiEpisodeCommentsByID(int id, int episode) async =>
      true;
}

// Fixture metadata must never issue a real danmaku lookup for synthetic id 0.
// All playback/native output/route lifecycle code remains the production path.
class _LocalDanmaku extends PlayerDanmakuController {
  _LocalDanmaku(DownloadController downloads)
      : super(isLocalPlayback: () => false, downloadController: downloads);
  @override
  Future<DanmakuLoadResult> fetchDanmaku(
          int id, String plugin, int episode) async =>
      DanmakuLoadResult.success(danmakus: const [], bangumiID: id);
}

class LifecycleQaPlayer extends PlayerController {
  LifecycleQaPlayer(ShaderAssetService shaders, DownloadController downloads,
      AudioController audio)
      : _fixtureDanmaku = _LocalDanmaku(downloads),
        super(shaders, downloads, audio);

  final PlayerDanmakuController _fixtureDanmaku;
  // The base constructor owns its late-final field. Override reads without
  // assigning it a second time; this substitution exists only in the QA entry.
  @override
  PlayerDanmakuController get danmaku => _fixtureDanmaku;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kReleaseMode ||
      (await PackageInfo.fromPlatform()).packageName !=
          'com.znbsf.kazumi.fluttertv.recoveryqa') {
    throw StateError('Requires isolated debug QA identity');
  }
  await TvMode.initialize();
  final root = await getApplicationSupportDirectory();
  await Hive.initFlutter('${root.path}/hive');
  await GStorage.init();
  await GStorage.putSetting(
      SettingsKeys.androidVideoRenderer, 'mediacodec_embed');
  await GStorage.putSetting(SettingsKeys.autoPlay, true);
  await GStorage.putSetting(SettingsKeys.autoPlayNext, false);
  await GStorage.putSetting(SettingsKeys.danmakuEnabledByDefault, false);
  await GStorage.putSetting(SettingsKeys.defaultPlaySpeed, 1.0);
  await GStorage.putSetting(SettingsKeys.playerLogLevel, 3);
  MediaKit.ensureInitialized();
  final module = createModule(register: (c) {
    c.module(coreModule);
    c.route('/', child: (_, __) => const _Home());
    c.route('/video/',
        provide: (s) => s
          ..add<VideoPageController>(_Video.new)
          ..add<PlayerController>(LifecycleQaPlayer.new),
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

class _Home extends StatelessWidget {
  const _Home();
  @override
  Widget build(BuildContext context) => Scaffold(
          body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final item in [
          ('H264 normal (auto emulator)', _normal, 'auto'),
          ('Controlled slow / rapid (auto)', _controlled, 'auto'),
          ('Controlled hardware / FFV1', _controlled, 'mediacodec_embed')
        ])
          Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton(
                  autofocus: item.$2 == _normal,
                  onPressed: () async {
                    await GStorage.putSetting(
                        SettingsKeys.androidVideoRenderer, item.$3);
                    if (!context.mounted) return;
                    debugPrint('LIFECYCLE_QA selected output=${item.$3}');
                    _selectedMedia = item.$2;
                    context.pushNamed('/video/',
                        arguments: OnlineVideoPlaybackArgs(
                            bangumiItem: BangumiItem(
                                id: 0,
                                type: 2,
                                name: 'Synthetic recovery',
                                nameCn: '兼容恢复验收',
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
                                info: ''),
                            plugin: Plugin.fromJson({
                              'name': 'Synthetic',
                              'baseURL': _base,
                              'userAgent': 'RecoveryPageQA'
                            }),
                            title: 'Controlled media',
                            src: '/fixture',
                            allowHistoryResume: false,
                            roads: [
                              Road(
                                  name: 'Fixture',
                                  data: ['/episode1'],
                                  identifier: ['第1集'])
                            ]));
                  },
                  child: Text(item.$1)))
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
    debugPrint('LIFECYCLE_QA enter ${identityHashCode(widget.player)}');
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final p = widget.player.playback;
      var decoder = 'not_initialized';
      try {
        decoder = p.hardwareDecoder;
      } catch (_) {
        // Diagnostics must not add a second exception before initialization.
      }
      debugPrint('LIFECYCLE_QA id=${identityHashCode(widget.player)} '
          'pos=${p.currentPosition.inMilliseconds} playing=${p.playing} '
          'blocked=${p.recoveryBlocksCompletion} completed=${p.completed} '
          'loading=${p.loading} nativeError=${p.recoveryHasNativeError} '
          'pending=${widget.player.pendingRecovery != null} '
          'decoder=$decoder episode=${widget.video.playbackEpisode.episode} '
          'tab=${widget.video.showTabBody} controls=${widget.player.panel.showVideoController} '
          'focus=${FocusManager.instance.primaryFocus?.debugLabel}');
    });
  }

  @override
  void dispose() {
    debugPrint('LIFECYCLE_QA leave ${identityHashCode(widget.player)}');
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
