import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/audio_controller.dart';

PlaybackState state({
  bool playing = true,
  AudioProcessingState processing = AudioProcessingState.ready,
  int positionMs = 10000,
  int bufferedMs = 60000,
  double speed = 1,
  int queueIndex = 0,
  bool seekable = true,
  bool canSkip = false,
  DateTime? updateTime,
}) =>
    PlaybackState(
      controls: [
        playing ? MediaControl.pause : MediaControl.play,
        if (canSkip) MediaControl.skipToNext,
      ],
      systemActions: {if (seekable) MediaAction.seek},
      processingState: processing,
      playing: playing,
      updatePosition: Duration(milliseconds: positionMs),
      bufferedPosition: Duration(milliseconds: bufferedMs),
      speed: speed,
      queueIndex: queueIndex,
      updateTime: updateTime,
    );

void main() {
  test('steady playback uses the extrapolated position and speed', () {
    final published = state(
      positionMs: 0,
      speed: 2,
      updateTime: DateTime.now().subtract(const Duration(seconds: 5)),
    );
    expect(
        AudioController.shouldPublishPlaybackState(published, state(speed: 2)),
        isFalse);
    expect(
        AudioController.shouldPublishPlaybackState(
            published, state(speed: 2, positionMs: 15000)),
        isTrue);
  });

  test('paused and buffering positions publish even short seeks', () {
    for (final processing in [
      AudioProcessingState.ready,
      AudioProcessingState.buffering,
    ]) {
      final playing = processing == AudioProcessingState.buffering;
      final published = state(playing: playing, processing: processing);
      expect(
          AudioController.shouldPublishPlaybackState(
              published, state(playing: playing, processing: processing)),
          isFalse);
      expect(
          AudioController.shouldPublishPlaybackState(
              published,
              state(
                  playing: playing, processing: processing, positionMs: 10500)),
          isTrue);
    }
  });

  test('buffer progress publishes only at the coarse tolerance', () {
    final published = state();
    for (final bufferedMs in [61000, 65000, 69999]) {
      expect(
          AudioController.shouldPublishPlaybackState(
              published, state(bufferedMs: bufferedMs)),
          isFalse);
    }
    for (final bufferedMs in [70000, 90000, 50000]) {
      expect(
          AudioController.shouldPublishPlaybackState(
              published, state(bufferedMs: bufferedMs)),
          isTrue);
    }
  });

  test('session controls are never swallowed', () {
    final published = state();
    for (final next in [
      state(playing: false),
      state(processing: AudioProcessingState.loading),
      state(processing: AudioProcessingState.completed),
      state(speed: 1.5),
      state(queueIndex: 1),
      state(seekable: false),
      state(canSkip: true),
    ]) {
      expect(
          AudioController.shouldPublishPlaybackState(published, next), isTrue);
    }
  });
}
