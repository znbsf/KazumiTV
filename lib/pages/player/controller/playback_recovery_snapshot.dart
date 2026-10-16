import 'package:media_kit/media_kit.dart';

/// Captured from typed Dart state before the failed player is released.
/// Track objects retain external subtitle/audio URI metadata as well as IDs.
class PlaybackRecoverySnapshot {
  PlaybackRecoverySnapshot(PlayerState state, {bool? intendedPlaying})
      : position = state.position,
        playing = intendedPlaying ?? state.playing,
        rate = state.rate,
        audio = state.track.audio,
        subtitle = state.track.subtitle;

  final Duration position;
  final bool playing;
  final double rate;
  final AudioTrack audio;
  final SubtitleTrack subtitle;
}

/// Each asynchronous operation targets the captured replacement, with a fresh
/// ownership check before continuing. Never uses the controller's latest player.
Future<bool> restoreRecoveredPlayer(Player player,
    PlaybackRecoverySnapshot snapshot, bool Function() isCurrent) async {
  if (!isCurrent()) return false;
  await player.setRate(snapshot.rate);
  if (!isCurrent()) return false;
  await player.setAudioTrack(snapshot.audio);
  if (!isCurrent()) return false;
  await player.setSubtitleTrack(snapshot.subtitle);
  if (!isCurrent()) return false;
  await player.seek(snapshot.position);
  if (!isCurrent()) return false;
  if (snapshot.playing) {
    await player.play();
  } else {
    await player.pause();
  }
  return isCurrent();
}
