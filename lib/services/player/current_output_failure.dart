import 'confirmed_playback_recovery.dart';

enum CurrentOutputFailure { releasedSession, initialization, firstFrameTimeout }

/// Shared by the native error and initial frame callbacks of one owned player.
/// Retirement is decided by ownership, never inferred from an error string.
class CurrentOutputFailureHandler {
  CurrentOutputFailureHandler(
      {required this.isCurrent, required this.abort, required this.report});
  final bool Function() isCurrent;
  final void Function() abort;
  final void Function(CurrentOutputFailure) report;
  bool _reported = false;
  bool get reported => _reported;

  void fail(CurrentOutputFailure failure) {
    if (!isCurrent() || _reported) return;
    _reported = true;
    abort();
    report(failure);
  }

  void observe(FirstFrameOutcome outcome, {required bool alreadyHandled}) {
    if (alreadyHandled) return;
    switch (outcome) {
      case FirstFrameOutcome.failed:
        fail(CurrentOutputFailure.initialization);
      case FirstFrameOutcome.timedOut:
        fail(CurrentOutputFailure.firstFrameTimeout);
      case FirstFrameOutcome.rendered:
      case FirstFrameOutcome.cancelled:
        break;
    }
  }
}
