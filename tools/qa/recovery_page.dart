// Debug-only, isolated identity. Uses the real video page and route ownership.
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

class _Source implements WebViewVideoSourceService {
  @override
  Stream<String> get onLog => const Stream.empty();
  @override
  Future<VideoSource> resolve(String episodeUrl, {required bool useLegacyParser,
      int offset = 0, Duration timeout = const Duration(seconds: 15)}) async {
    debugPrint('RECOVERY_PAGE resolve $episodeUrl');
    return const VideoSource(url: 'http://10.0.2.2:18743/sample.mkv',
        offset: 17, type: VideoSourceType.online);
  }
  @override
  void cancel() {}
  @override
  Future<void> dispose() async {}
}

// Avoid unrelated public comment requests; playback and UI remain production.
class _Video extends VideoPageController {
  _Video(HistoryController history, IDownloadRepository downloads,
      IDownloadManager manager) : super(history, downloads, manager,
          videoSourceService: _Source());
  @override
  Future<bool> queryBangumiEpisodeCommentsByID(int id, int episode) async => true;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kReleaseMode || (await PackageInfo.fromPlatform()).packageName !=
      'com.znbsf.kazumi.fluttertv.recoveryqa') {
    throw StateError('Requires isolated debug QA identity');
  }
  await TvMode.initialize();
  final root = await getApplicationSupportDirectory();
  await Hive.initFlutter('${root.path}/hive');
  await GStorage.init();
  await GStorage.putSetting(SettingsKeys.androidVideoRenderer, 'mediacodec_embed');
  await GStorage.putSetting(SettingsKeys.autoPlay, false);
  await GStorage.putSetting(SettingsKeys.autoPlayNext, true);
  await GStorage.putSetting(SettingsKeys.danmakuEnabledByDefault, false);
  await GStorage.putSetting(SettingsKeys.defaultPlaySpeed, 1.25);
  await GStorage.putSetting(SettingsKeys.playerLogLevel, 3);
  MediaKit.ensureInitialized();
  final module = createModule(register: (c) {
    c.module(coreModule);
    c.route('/', child: (_, __) => const _Home());
    c.route('/video/', provide: (s) => s
      ..add<VideoPageController>(_Video.new)
      ..add<PlayerController>(PlayerController.new), child: (context, state) {
        final player = context.read<PlayerController>();
        final video = context.read<VideoPageController>();
        return _Observe(player: player, video: video, child: VideoPage(
            args: state.arguments as VideoPlaybackArgs,
            playerController: player, videoPageController: video,
            historyController: inject<HistoryController>(),
            downloadController: inject<DownloadController>()));
      });
  });
  runApp(ModularApp(module: module, navigatorKey: rootNavigatorKey,
      navigatorObservers: [KazumiDialog.observer, rootRouteObserver],
      child: Builder(builder: (context) => MaterialApp.router(
          theme: ThemeData(brightness: Brightness.dark),
          routerConfig: ModularApp.routerConfigOf(context),
          builder: (_, child) => TvAppShell(child: child!)))));
}

class _Home extends StatelessWidget {
  const _Home();
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: FilledButton(
      autofocus: true, onPressed: () => context.pushNamed('/video/', arguments:
        OnlineVideoPlaybackArgs(bangumiItem: BangumiItem(id: 0, type: 2,
          name: 'Synthetic recovery', nameCn: '兼容恢复验收', summary: '',
          airDate: '', airWeekday: 0, rank: 0, images: {}, tags: [], alias: [],
          ratingScore: 0, votes: 0, votesCount: List.filled(10, 0), info: ''),
          plugin: Plugin.fromJson({'name': 'Synthetic',
            'baseURL': 'http://10.0.2.2:18743', 'userAgent': 'RecoveryPageQA'}),
          title: 'Controlled media', src: '/fixture', allowHistoryResume: false,
          roads: [Road(name: 'Fixture', data: ['/episode1', '/episode2'],
              identifier: ['第1集', '第2集'])])), child: const Text('Open real player'))));
}

class _Observe extends StatefulWidget {
  const _Observe({required this.player, required this.video, required this.child});
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
    debugPrint('RECOVERY_PAGE enter ${identityHashCode(widget.player)}');
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final p = widget.player.playback;
      debugPrint('RECOVERY_PAGE id=${identityHashCode(widget.player)} '
          'pos=${p.currentPosition.inMilliseconds} playing=${p.playing} '
          'blocked=${p.recoveryBlocksCompletion} completed=${p.completed} '
          'loading=${p.loading} nativeError=${p.recoveryHasNativeError} '
          'pending=${widget.player.pendingRecovery != null} '
          'decoder=${p.hardwareDecoder} episode=${widget.video.playbackEpisode.episode} '
          'tab=${widget.video.showTabBody} controls=${widget.player.panel.showVideoController} '
          'focus=${FocusManager.instance.primaryFocus?.debugLabel}');
    });
  }
  @override
  void dispose() {
    debugPrint('RECOVERY_PAGE leave ${identityHashCode(widget.player)}');
    timer?.cancel();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => widget.child;
}
