import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/confirmed_playback_recovery.dart';
import 'package:kazumi/services/player/player_error_mapper.dart';

void main() {
  test('native command completion is not decoding readiness', () async {
    final frame = Completer<void>();
    final aborted = Completer<void>();
    var finished = false;
    final result = waitForRecoveryFrame(
        firstFrame: frame.future,
        aborted: aborted.future,
        isCurrent: () => true).then((value) {
      finished = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    frame.complete();
    expect(await result, isTrue);
  });
  test('native failure or route exit aborts without waiting for a frame',
      () async {
    final frame = Completer<void>();
    final aborted = Completer<void>();
    final result = waitForRecoveryFrame(
        firstFrame: frame.future,
        aborted: aborted.future,
        isCurrent: () => true);
    aborted.complete();
    expect(await result, isFalse);
    frame.complete();
  });
  test('late frame cannot mark a replaced session successful', () async {
    expect(
        await waitForRecoveryFrame(
            firstFrame: Future.value(),
            aborted: Completer<void>().future,
            isCurrent: () => false),
        isFalse);
  });
  test('unresponsive native output has a bounded recovery wait', () async {
    expect(
        await waitForRecoveryFrame(
            firstFrame: Completer<void>().future,
            aborted: Completer<void>().future,
            isCurrent: () => true,
            timeout: const Duration(milliseconds: 5)),
        isFalse);
  });
  test('late software codec failure is actionable without debug errors enabled',
      () {
    const error = "Failed to initialize a decoder for codec 'ffv1'.";
    expect(PlayerErrorMapper.toActionableMessage(error, isBuffering: false),
        contains('播放发生异常'));
    expect(
        PlayerErrorMapper.toActionableMessage(error,
            isBuffering: false, softwareRecovery: true),
        contains('软件兼容播放失败'));
  });
}
