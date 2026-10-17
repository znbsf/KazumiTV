import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/current_output_failure.dart';
import 'package:kazumi/services/player/confirmed_playback_recovery.dart';
import 'package:kazumi/services/player/player_error_mapper.dart';

void main() {
  test('late failed frame after replacement cannot mutate the new session',
      () async {
    var current = true;
    final frame = Completer<void>();
    final handler = CurrentOutputFailureHandler(
        isCurrent: () => current,
        abort: () => fail('old abort'),
        report: (_) => fail('old report'));
    final result = observeFirstFrame(
            firstFrame: frame.future, cancelled: Completer<void>().future)
        .then((outcome) => handler.observe(outcome, alreadyHandled: false));
    current = false;
    frame.completeError(StateError('late output failure'));
    await result;
    handler.observe(FirstFrameOutcome.timedOut, alreadyHandled: false);
    expect(handler.reported, isFalse);
  });

  test(
      'current disposed aborts and reports once, never authorizes software recovery',
      () {
    var aborts = 0;
    final reports = <CurrentOutputFailure>[];
    final handler = CurrentOutputFailureHandler(
        isCurrent: () => true, abort: () => aborts++, report: reports.add);
    handler.fail(CurrentOutputFailure.releasedSession);
    handler.fail(CurrentOutputFailure.releasedSession);
    expect(aborts, 1);
    expect(reports, [CurrentOutputFailure.releasedSession]);
    expect(
        PlayerErrorMapper.toActionableMessage(
            AssertionError('[Player] has been disposed'),
            isBuffering: false),
        isNotNull);
    expect(
        isDirectDecoderFailure(
            prefix: 'vd', text: '[Player] has been disposed'),
        isFalse);
  });
  test('retired native error cannot abort or report against replacement', () {
    final handler = CurrentOutputFailureHandler(
        isCurrent: () => false,
        abort: () => fail('retired abort'),
        report: (_) => fail('retired report'));
    handler.fail(CurrentOutputFailure.releasedSession);
    handler.observe(FirstFrameOutcome.failed, alreadyHandled: false);
    expect(handler.reported, isFalse);
  });
  test(
      'platform initialization error without stream.error reaches actual handler once',
      () async {
    final platform = Completer<void>();
    final aborted = Completer<void>();
    var aborts = 0;
    final reports = <CurrentOutputFailure>[];
    final handler = CurrentOutputFailureHandler(
        isCurrent: () => true,
        abort: () {
          aborts++;
          aborted.complete();
        },
        report: reports.add);
    final observing = observeFirstFrame(
            firstFrame: platform.future, cancelled: aborted.future)
        .then((outcome) => handler.observe(outcome, alreadyHandled: false));
    platform.completeError(StateError('platform initialization'));
    await observing;
    handler.observe(FirstFrameOutcome.timedOut, alreadyHandled: false);
    expect(aborts, 1);
    expect(reports, [CurrentOutputFailure.initialization]);
  });
  test('normal frame, exit and already handled failure do not report', () {
    final handler = CurrentOutputFailureHandler(
        isCurrent: () => true,
        abort: () => fail('unexpected abort'),
        report: (_) => fail('unexpected report'));
    handler.observe(FirstFrameOutcome.rendered, alreadyHandled: false);
    handler.observe(FirstFrameOutcome.cancelled, alreadyHandled: false);
    handler.observe(FirstFrameOutcome.failed, alreadyHandled: true);
    expect(handler.reported, isFalse);
  });
}
