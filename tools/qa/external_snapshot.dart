// Native external-track snapshot fixture; NOT the decoder-failure UI chain.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
// ignore: depend_on_referenced_packages
import 'package:package_info_plus/package_info_plus.dart';
import 'package:kazumi/pages/player/controller/playback_recovery_snapshot.dart';

const base = String.fromEnvironment('RECOVERY_QA_BASE',
    defaultValue: 'http://10.0.2.2:18743');
const audio = String.fromEnvironment('RECOVERY_QA_AUDIO',
    defaultValue: '$base/external-a.wav');
const subtitle = String.fromEnvironment('RECOVERY_QA_SUBTITLE',
    defaultValue: '$base/external-b.srt');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kReleaseMode ||
      (await PackageInfo.fromPlatform()).packageName !=
          'com.znbsf.kazumi.fluttertv.recoveryqa') {
    throw StateError('Requires isolated debug QA identity');
  }
  MediaKit.ensureInitialized();
  runApp(const MaterialApp(home: _Probe()));
}

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  Player? player;
  VideoController? video;
  int epoch = 0;
  bool busy = false;
  String status = 'External native snapshot only; press Run';

  void report(String value) {
    debugPrint('EXTERNAL_SNAPSHOT $value');
    if (mounted) setState(() => status = value);
  }

  Future<void> run() async {
    final token = ++epoch;
    bool current() => mounted && token == epoch;
    var phase = 'initializing';
    setState(() => busy = true);
    Future<void> execute() async {
      final old = player;
      player = null;
      video = null;
      if (old != null) await old.dispose();
      if (!current()) return;
      Future<Player> create() async {
        final p = Player();
        player = p;
        final v = VideoController(p,
            configuration: const VideoControllerConfiguration(
                vo: 'gpu', hwdec: 'no', enableAndroidSurfaceProducer: false));
        setState(() => video = v);
        await p.open(Media('$base/sample.mkv'), play: false);
        await v.waitUntilFirstFrameRendered;
        return p;
      }

      final first = await create();
      if (!current()) return;
      phase = 'selecting external tracks';
      await first.setAudioTrack(AudioTrack.uri(audio));
      if (!current()) return;
      await first.setSubtitleTrack(SubtitleTrack.uri(subtitle));
      if (!current()) return;
      await first.setRate(1.25);
      if (!current()) return;
      await first.seek(const Duration(seconds: 17));
      if (!current()) return;
      while (current() &&
          ((first.state.position.inMilliseconds - 17000).abs() > 500 ||
              first.state.rate != 1.25 ||
              first.state.playing)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!current()) return;
      final snapshot =
          PlaybackRecoverySnapshot(first.state, intendedPlaying: false);
      if (snapshot.audio.id != audio ||
          !snapshot.audio.uri ||
          snapshot.subtitle.id != subtitle ||
          !snapshot.subtitle.uri) {
        throw StateError('External typed snapshot not established');
      }
      report('captured external URI tracks position=${snapshot.position} '
          'rate=${snapshot.rate} playing=${snapshot.playing}; disposing old player');
      player = null;
      video = null;
      await first.dispose();
      if (!current()) return;
      final replacement = await create();
      if (!current()) return;
      phase = 'restoring snapshot';
      final restored =
          await restoreRecoveredPlayer(replacement, snapshot, current);
      if (!current()) return;
      if (!restored) throw StateError('Snapshot restore command failed');
      phase = 'waiting for restored state events';
      // Native command completion precedes the asynchronous position event.
      // Require the whole paused state to remain valid for 500 ms, within the
      // existing 30-second experiment deadline, before declaring typed PASS.
      final stable = Stopwatch();
      while (current()) {
        final state = replacement.state;
        final matches = state.track.audio == snapshot.audio &&
            state.track.subtitle == snapshot.subtitle &&
            (state.position - snapshot.position).inMilliseconds.abs() <= 500 &&
            state.rate == snapshot.rate &&
            state.playing == snapshot.playing &&
            !state.completed;
        if (matches) {
          stable.start();
        } else {
          stable.stop();
          stable.reset();
        }
        if (stable.elapsed >= const Duration(milliseconds: 500)) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!current()) return;
      report(
          'typed restore PASS; paused position=${replacement.state.position}; '
          'rate=${replacement.state.rate} playing=${replacement.state.playing} '
          'externalTracks=true stableMs=500; '
          'inspect EXTERNAL B subtitle, then press Play for audible evidence');
    }

    try {
      await execute().timeout(const Duration(seconds: 30));
    } catch (error) {
      if (current()) {
        report('not_passed: ${error.runtimeType} phase=$phase '
            'position=${player?.state.position} rate=${player?.state.rate} '
            'playing=${player?.state.playing}');
      }
    } finally {
      if (token == epoch) epoch++;
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    epoch++;
    unawaited(player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
          body: Column(children: [
        Expanded(
            child: video == null
                ? const SizedBox()
                : Video(controller: video!, controls: NoVideoControls)),
        Text(status),
        Row(children: [
          FilledButton(
              autofocus: true,
              onPressed: busy ? null : run,
              child: const Text('Run external snapshot')),
          FilledButton(
              onPressed: busy ? null : () => player?.play(),
              child: const Text('Play / hear external audio')),
        ]),
      ]));
}
