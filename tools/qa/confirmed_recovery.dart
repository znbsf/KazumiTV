// Isolated native integration fixture. Never imported by the production entry.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/widget/tv_app_shell.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/player/tv_playback_info.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart' as canvas;
import 'package:media_kit/media_kit.dart';
// ignore: depend_on_referenced_packages
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/player/player_item_surface.dart';
import 'package:kazumi/pages/player/tv_recovery_confirmation.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/player/audio_controller.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';
import 'package:kazumi/services/storage/storage.dart';

class _Downloads implements DownloadController {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// This fixture validates native playback and focus, not canvas danmaku rendering.
class _Canvas implements canvas.DanmakuController {
  @override
  VoidCallback get clear => () {};
  @override
  VoidCallback get pause => () {};
  @override
  VoidCallback get resume => () {};
  @override
  canvas.DanmakuOption get option => canvas.DanmakuOption();
  @override
  ValueChanged<canvas.DanmakuOption> get updateOption => (_) {};
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void record(String value) => debugPrint('RECOVERY_QA $value');
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kReleaseMode ||
      (await PackageInfo.fromPlatform()).packageName !=
          'com.znbsf.kazumi.fluttertv.recoveryqa') {
    throw StateError('Requires isolated debug QA identity');
  }
  await TvMode.initialize();
  final root = await getApplicationSupportDirectory();
  final file = File('${root.path}/qa-config.json');
  final config = file.existsSync()
      ? jsonDecode(await file.readAsString()) as Map<String, dynamic>
      : <String, dynamic>{};
  final path = config['http'] == true
      ? 'http://10.0.2.2:18743/sample.mkv'
      : '${root.path}/sample.mkv';
  await Hive.initFlutter('${root.path}/hive');
  await GStorage.init();
  await GStorage.putSetting(SettingsKeys.androidVideoRenderer,
      config['output'] ?? 'mediacodec_embed');
  await GStorage.putSetting(SettingsKeys.autoPlay, config['playing'] == true);
  await GStorage.putSetting(SettingsKeys.defaultPlaySpeed, 1.25);
  await GStorage.putSetting(SettingsKeys.playerLogLevel, 3);
  await GStorage.putSetting(SettingsKeys.showPlayerError, false);
  MediaKit.ensureInitialized();
  runApp(MaterialApp(
      navigatorKey: rootNavigatorKey,
      builder: (_, child) => TvAppShell(child: child!),
      home: Probe(path: path)));
}

class Probe extends StatefulWidget {
  const Probe({super.key, required this.path});
  final String path;
  @override
  State<Probe> createState() => _Probe();
}

class _Probe extends State<Probe> {
  final controller =
      PlayerController(ShaderAssetService(), _Downloads(), AudioController());
  final presenter = TvPlaybackInfoPresenter();
  final startFocus = FocusNode();
  Timer? timer;
  bool opened = false, prompt = false;
  int logged = 0;
  String status = 'Ready: software-supported MJPEG fixture';
  @override
  void initState() {
    super.initState();
    controller.danmaku.canvasController = _Canvas();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      controller.syncPlaybackState();
      final p = controller.playback;
      if (logged > controller.debug.playerLog.length) logged = 0;
      for (final line in controller.debug.playerLog.skip(logged)) {
        if (line.contains('Software decoding fallback') ||
            line.contains('Using software decoding')) record(line);
      }
      logged = controller.debug.playerLog.length;
      record(
          'state playing=${p.playing} pos=${p.currentPosition.inMilliseconds} completed=${p.completed} blocked=${p.recoveryBlocksCompletion} pending=${controller.pendingRecovery != null}');
      final session = controller.pendingRecovery;
      if (session != null && !prompt && mounted) {
        prompt = true;
        record('confirmation');
        var accepted = false;
        presenter
            .show(context,
                fallbackFocus: startFocus,
                builder: (_) => TvRecoveryConfirmation(
                      onCancel: presenter.close,
                      onConfirm: () {
                        accepted = true;
                        presenter.close();
                      },
                    ))
            .then((_) async {
          if (!mounted) return;
          if (accepted != true) {
            controller.recovery.cancel(session);
            record('cancelled unchanged');
            setState(() => status = 'Cancelled: no replacement');
            return;
          }
          record('confirmed');
          final result = await controller.recoverWithSoftware(session);
          record(
              'result=$result rate=${controller.playback.mediaPlayer?.state.rate} decoder=${controller.playback.hardwareDecoder} storedOutput=${GStorage.getSetting(SettingsKeys.androidVideoRenderer)}');
          if (mounted)
            setState(() =>
                status = 'Recovered=$result; original play state restored.');
        });
      }
    });
  }

  Future<void> start() async {
    if (opened) {
      await controller.playOrPause();
      return;
    }
    opened = true;
    final ok = await controller.init(params(17));
    record('initialized=$ok decoder=${controller.playback.hardwareDecoder}');
    if (mounted)
      setState(() => status = 'Opened; waiting for decoder evidence');
  }

  PlaybackInitParams params(int offset) => PlaybackInitParams(
        videoUrl: widget.path,
        offset: offset,
        isLocalPlayback: !widget.path.startsWith('http'),
        bangumiId: 1,
        pluginName: 'Synthetic MJPEG',
        episode: 1,
        danmakuEpisodeNumber: 1,
        httpHeaders: const {'X-Recovery-Fixture': 'preserved'},
        adBlockerEnabled: false,
        episodeTitle: 'Fixture',
        referer: '',
        currentRoad: 0,
        onPlaybackError: (message) => record('generic-error $message'),
      );

  Future<void> replace({bool rapid = false}) async {
    prompt = false;
    logged = 0;
    final results = await Future.wait([
      if (rapid) controller.init(params(5)),
      controller.init(params(17)),
    ]);
    record(
        'replaced rapid=$rapid results=$results decoder=${controller.playback.hardwareDecoder} storedOutput=${GStorage.getSetting(SettingsKeys.androidVideoRenderer)}');
  }

  @override
  void dispose() {
    presenter.close();
    startFocus.dispose();
    timer?.cancel();
    controller.beginShutdown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          await controller.stop();
          await SystemNavigator.pop();
        },
        child: Scaffold(
            body: Stack(children: [
          Positioned.fill(
              child: PlayerItemSurface(playerController: controller)),
          Positioned(
              top: 12,
              left: 12,
              child: Text(status,
                  style: const TextStyle(
                      color: Colors.white, backgroundColor: Colors.black))),
          Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
            FilledButton(
                focusNode: startFocus,
                autofocus: true,
                onPressed: start,
                child: const Text('Start / Play-pause')),
            FilledButton(onPressed: replace, child: const Text('New session')),
            FilledButton(
                onPressed: () => replace(rapid: true),
                child: const Text('Rapid replace')),
          ])),
        ])),
      );
}
