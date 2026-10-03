// Diagnostic entry only: direct Player + Video, no Kazumi routes/owner/history.
// Configuration and self-generated media come from the task's loopback server.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';

const _base = 'http://10.0.2.2:18792';
void _log(String event, [Map<String, Object?> values = const {}]) {
  debugPrint('DECODER_PROBE ${jsonEncode({
        'event': event,
        'utc': DateTime.now().toUtc().toIso8601String(),
        ...values
      })}');
}

Future<List<int>> _fetch(String path) async {
  final client = HttpClient();
  try {
    final response =
        await (await client.getUrl(Uri.parse('$_base/$path'))).close();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    return await response.fold<List<int>>([], (a, b) => a..addAll(b));
  } finally {
    client.close();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final config = jsonDecode(utf8.decode(await _fetch('config.json')))
      as Map<String, dynamic>;
  runApp(MaterialApp(home: _Probe(config)));
}

class _Probe extends StatefulWidget {
  const _Probe(this.config);
  final Map<String, dynamic> config;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  Player? player;
  VideoController? video;
  Timer? heartbeat;
  int ticks = 0;
  int errors = 0;
  String status = 'starting';
  final subscriptions = <StreamSubscription<dynamic>>[];
  Map<String, dynamic> get config => widget.config;
  @override
  void initState() {
    super.initState();
    heartbeat = Timer.periodic(const Duration(seconds: 1), (_) {
      _log('heartbeat',
          {'tick': ++ticks, 'case': config['case'], 'status': status});
    });
    unawaited(_run());
  }

  Future<Player> _create() async {
    final current = Player(
        configuration: const PlayerConfiguration(logLevel: MPVLogLevel.debug));
    subscriptions.add(current.stream.log.listen((event) => _log('mpv',
        {'prefix': event.prefix, 'level': event.level, 'text': event.text})));
    subscriptions.add(current.stream.error.listen((event) {
      errors++;
      _log('error', {'text': event});
    }));
    subscriptions.add(current.stream.completed.listen((done) {
      if (done) {
        _log(
            'completed', {'positionMs': current.state.position.inMilliseconds});
      }
    }));
    final native = current.platform as NativePlayer;
    await native.setProperty('ao', config['ao'] as String? ?? 'audiotrack');
    if (config['cacheDirectory'] == true) {
      await native.setProperty(
          'demuxer-cache-dir', (await getTemporaryDirectory()).path);
    }
    for (final option
        in (config['properties'] as Map<String, dynamic>? ?? {}).entries) {
      await native.setProperty(option.key, option.value.toString());
      _log('property-configured', {'name': option.key, 'value': option.value});
    }
    if (config['filter'] == true) {
      await native.setProperty('af', 'scaletempo2=max-speed=8');
    }
    if (config['audio'] == false) await current.setAudioTrack(AudioTrack.no());
    player = current;
    if (config['video'] != false) {
      video = VideoController(current,
          configuration: VideoControllerConfiguration(
              vo: config['vo'] as String? ?? 'gpu',
              hwdec: config['hwdec'] as String? ?? 'no',
              enableHardwareAcceleration: config['hwdec'] != 'no',
              enableAndroidSurfaceProducer: false,
              androidAttachSurfaceAfterVideoParameters: false));
    }
    if (mounted) setState(() {});
    await WidgetsBinding.instance.endOfFrame;
    return current;
  }

  Future<void> _run() async {
    try {
      _log('start', {'config': config});
      final name = config['media'] as String? ?? 'original.mp4';
      String source = '$_base/$name';
      if (config['protocol'] == 'ffmpeg') source = 'ffmpeg://$source';
      if (config['local'] == true) {
        final data = await _fetch(name);
        final file =
            File('${(await getTemporaryDirectory()).path}/decoder-probe-$name');
        await file.writeAsBytes(data, flush: true);
        source = file.uri.toString();
        _log('local-media',
            {'bytes': data.length, 'sha256': sha256.convert(data).toString()});
      }
      var current = await _create();
      status = 'first open';
      await current.open(Media(source));
      _log('first-open-complete');
      if (config['switch'] != null) {
        await Future<void>.delayed(const Duration(seconds: 3));
        await current.pause();
        _log('before-switch', {
          'positionMs': current.state.position.inMilliseconds,
          'mode': config['switch']
        });
        if (config['switch'] == 'recreate') {
          video = null;
          if (mounted) setState(() {});
          await WidgetsBinding.instance.endOfFrame;
          await current.dispose();
          _log('old-disposed');
          current = await _create();
        }
        status = 'second open';
        await current.open(Media(source));
        _log('second-open-complete');
        await Future<void>.delayed(const Duration(seconds: 2));
        if (config['property'] == true) {
          _log('before-property');
          final vo = await (current.platform as NativePlayer).getProperty('vo');
          _log('after-property', {'vo': vo});
        }
      }
      await Future<void>.delayed(
          Duration(seconds: config['waitSeconds'] as int? ?? 18));
      _log('result', {
        'errors': errors,
        'completed': current.state.completed,
        'playing': current.state.playing,
        'positionMs': current.state.position.inMilliseconds,
        'durationMs': current.state.duration.inMilliseconds,
        'audioTracks': current.state.tracks.audio
            .map((a) => '${a.id}:${a.title}:${a.codec}')
            .toList(),
        'case': config['case']
      });
      status = 'done';
      await current.pause();
      if (mounted) setState(() {});
    } catch (error, stack) {
      _log('exception', {'error': error.toString(), 'stack': stack.toString()});
      status = 'failed';
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    heartbeat?.cancel();
    for (final s in subscriptions) {
      unawaited(s.cancel());
    }
    unawaited(player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        if (video != null)
          Positioned.fill(
              child: Video(controller: video!, controls: NoVideoControls)),
        Positioned(
            top: 20,
            left: 20,
            child: Text('${config['case']} | $status | errors $errors',
                style: const TextStyle(color: Colors.white, fontSize: 24)))
      ]));
}
