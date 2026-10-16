import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:kazumi/pages/player/controller/playback_recovery_snapshot.dart';

class _Player implements Player {
  final calls = <String>[];
  Completer<void>? audioWait;
  AudioTrack? audio;
  SubtitleTrack? subtitle;
  @override
  Future<void> setRate(double value) async {
    calls.add('rate:$value');
  }

  @override
  Future<void> setAudioTrack(AudioTrack value) async {
    calls.add('audio');
    audio = value;
    await audioWait?.future;
  }

  @override
  Future<void> setSubtitleTrack(SubtitleTrack value) async {
    calls.add('subtitle');
    subtitle = value;
  }

  @override
  Future<void> seek(Duration value) async {
    calls.add('seek:${value.inMilliseconds}');
  }

  @override
  Future<void> play() async {
    calls.add('play');
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('native failure pause does not erase explicit playback intent', () {
    const failedState = PlayerState(playing: false);
    expect(PlaybackRecoverySnapshot(failedState, intendedPlaying: true).playing,
        isTrue);
    expect(
        PlaybackRecoverySnapshot(failedState, intendedPlaying: false).playing,
        isFalse);
  });
  for (final playing in [false, true]) {
    test(
        'restores exact position/rate/external tracks and playing=$playing in order',
        () async {
      final audio = AudioTrack.uri('https://example.org/audio.m4a');
      final sub = SubtitleTrack.uri('https://example.org/sub.vtt');
      final snapshot = PlaybackRecoverySnapshot(PlayerState(
        playing: playing,
        position: const Duration(milliseconds: 92751),
        rate: 1.25,
        track: Track(audio: audio, subtitle: sub),
      ));
      final player = _Player();
      expect(
          await restoreRecoveredPlayer(player, snapshot, () => true), isTrue);
      expect(player.calls, [
        'rate:1.25',
        'audio',
        'subtitle',
        'seek:92751',
        playing ? 'play' : 'pause'
      ]);
      expect(identical(player.audio, audio), isTrue);
      expect(identical(player.subtitle, sub), isTrue);
    });
  }
  test(
      'change episode during async track restore cannot seek or resume old player',
      () async {
    final player = _Player()..audioWait = Completer<void>();
    var current = true;
    final future = restoreRecoveredPlayer(
        player,
        PlaybackRecoverySnapshot(const PlayerState(playing: true)),
        () => current);
    await Future<void>.delayed(Duration.zero);
    current = false;
    player.audioWait!.complete();
    expect(await future, isFalse);
    expect(player.calls, ['rate:1.0', 'audio']);
  });
}
