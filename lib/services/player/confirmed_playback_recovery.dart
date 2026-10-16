import 'dart:async';

/// Opening media only accepts a native command; it does not prove decoding.
Future<bool> waitForRecoveryFrame({
  required Future<void> firstFrame,
  required Future<void> aborted,
  required bool Function() isCurrent,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final rendered = await Future.any<bool>([
    firstFrame.then((_) => true, onError: (Object _) => false),
    aborted.then((_) => false),
  ]).timeout(timeout, onTimeout: () => false);
  return rendered && isCurrent();
}

/// Explicit failure evidence from the pinned mpv decoder, never URL/error-text
/// heuristics or buffering/completion alone.
bool isDirectDecoderFailure({required String prefix, required String text}) =>
    prefix == 'vd' && text.trim() == 'Software decoding fallback is disabled.';

enum RecoveryPhase {
  watching,
  awaitingConfirmation,
  cancelled,
  recovering,
  recovered,
  failed
}

/// Per-media ownership token. Neither a late dialog nor a retired player's log
/// can authorize a replacement for a newer media session.
class RecoverySession {
  RecoverySession._();
  RecoveryPhase phase = RecoveryPhase.watching;
  bool directOutput = false;
  bool get blocksAutoNext =>
      phase != RecoveryPhase.watching && phase != RecoveryPhase.recovered;
}

class ConfirmedPlaybackRecovery {
  RecoverySession? _current;

  RecoverySession begin() => _current = RecoverySession._();
  bool owns(RecoverySession session) => identical(_current, session);
  void invalidate() => _current = null;

  bool reportFailure(RecoverySession session) {
    if (!owns(session) ||
        !session.directOutput ||
        session.phase != RecoveryPhase.watching) return false;
    session.phase = RecoveryPhase.awaitingConfirmation;
    return true;
  }

  bool confirm(RecoverySession session) {
    if (!owns(session) || session.phase != RecoveryPhase.awaitingConfirmation)
      return false;
    session.phase = RecoveryPhase.recovering;
    return true;
  }

  void cancel(RecoverySession session) {
    if (owns(session) && session.phase == RecoveryPhase.awaitingConfirmation) {
      session.phase = RecoveryPhase.cancelled;
    }
  }

  void finish(RecoverySession session, {required bool succeeded}) {
    if (owns(session) && session.phase == RecoveryPhase.recovering) {
      session.phase =
          succeeded ? RecoveryPhase.recovered : RecoveryPhase.failed;
    }
  }

  Future<void> settle(
    RecoverySession session, {
    required bool succeeded,
    required Future<void> Function() stop,
    required void Function(bool succeeded) applyResult,
  }) async {
    if (!owns(session)) return;
    if (!succeeded) await stop();
    if (!owns(session)) return;
    finish(session, succeeded: succeeded);
    applyResult(succeeded);
  }
}
