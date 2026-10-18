import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/confirmed_playback_recovery.dart';

void main() {
  test('late cleanup cannot change a newer playback completion guard',
      () async {
    final gate = ConfirmedPlaybackRecovery();
    final old = gate.begin()..directOutput = true;
    gate.reportFailure(old);
    gate.confirm(old);
    final disposed = Completer<void>();
    var applied = false;
    final settling = gate.settle(old,
        succeeded: false,
        stop: () => disposed.future,
        applyResult: (_) => applied = true);
    final next = gate.begin();
    disposed.complete();
    await settling;
    expect(applied, isFalse);
    expect(next.blocksAutoNext, isFalse);
  });

  test('successful single recovery allows normal EOF, never a second retry',
      () async {
    final gate = ConfirmedPlaybackRecovery();
    final session = gate.begin()..directOutput = true;
    gate.reportFailure(session);
    gate.confirm(session);
    var stopped = false;
    await gate.settle(session, succeeded: true, stop: () async {
      stopped = true;
    }, applyResult: (_) {});
    expect(stopped, isFalse);
    expect(session.blocksAutoNext, isFalse);
    expect(gate.reportFailure(session), isFalse);
  });
  test('only pinned decoder evidence qualifies; network, EOF and copy do not',
      () {
    expect(
        isDirectDecoderFailure(
            prefix: 'vd',
            text:
                'Attempting next decoding method after failure of h264_mediacodec-mediacodec.\n'),
        isTrue);
    for (final prefix in ['ffmpeg', 'demux', '']) {
      expect(
          isDirectDecoderFailure(
              prefix: prefix, text: 'Software decoding fallback is disabled.'),
          isFalse);
    }
    for (final text in [
      'Software decoding fallback is disabled.',
      'Could not open codec.',
      'Could not set codec parameters.',
      'Attempting next decoding method after failure of h264_mediacodec-mediacodec-copy.',
      '[Player] has been disposed',
      'TimeoutException',
      'No audio',
      'HTTP 403',
      'EOF',
      'buffering',
      'Error while decoding frame (hardware decoding)!'
    ]) {
      expect(isDirectDecoderFailure(prefix: 'vd', text: text), isFalse);
    }
    final gate = ConfirmedPlaybackRecovery();
    expect(gate.reportFailure(gate.begin()), isFalse);
  });

  test(
      'cancel never authorizes recovery or repeat prompts; suppresses failed EOF',
      () {
    final gate = ConfirmedPlaybackRecovery();
    final session = gate.begin()..directOutput = true;
    expect(gate.confirm(session), isFalse);
    expect(gate.reportFailure(session), isTrue);
    expect(session.blocksAutoNext, isTrue);
    gate.cancel(session);
    expect(gate.confirm(session), isFalse);
    expect(gate.reportFailure(session), isFalse);
    expect(session.blocksAutoNext, isTrue);
  });

  test('confirmation is single use even when recovery fails', () {
    final gate = ConfirmedPlaybackRecovery();
    final session = gate.begin()..directOutput = true;
    gate.reportFailure(session);
    expect(gate.confirm(session), isTrue);
    expect(gate.confirm(session), isFalse);
    gate.finish(session, succeeded: false);
    expect(gate.reportFailure(session), isFalse);
    expect(gate.confirm(session), isFalse);
  });

  test('change media and shutdown invalidate late logs and dialog results', () {
    final gate = ConfirmedPlaybackRecovery();
    final old = gate.begin()..directOutput = true;
    gate.reportFailure(old);
    final next = gate.begin()..directOutput = true;
    expect(gate.confirm(old), isFalse);
    expect(gate.reportFailure(old), isFalse);
    gate.cancel(old);
    expect(next.phase, RecoveryPhase.watching);
    expect(next.blocksAutoNext, isFalse);
    gate.invalidate();
    expect(gate.reportFailure(next), isFalse);
  });
}
