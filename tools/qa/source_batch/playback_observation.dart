// QA-only state sampling. No player control, transport or raw error text.
import 'dart:async';

Duration? qaPlaybackObservationWindow(Object? seconds) {
  if (seconds == null) return null;
  if (seconds is! int || seconds < 10 || seconds > 15) {
    throw const FormatException(
        'QA playback observation requires 10..15 seconds');
  }
  return Duration(seconds: seconds);
}

class QaPlaybackState {
  const QaPlaybackState(
      {required this.positionMs,
      required this.playing,
      required this.buffering,
      required this.completed,
      required this.bufferMs,
      required this.durationMs,
      required this.errorCount});
  final int positionMs, bufferMs, durationMs, errorCount;
  final bool playing, buffering, completed;
  Map<String, Object> record(int elapsedMs) => {
        'elapsed_ms': elapsedMs,
        'position_ms': positionMs,
        'playing': playing,
        'buffering': buffering,
        'completed': completed,
        'buffer_ms': bufferMs,
        'duration_ms': durationMs,
        'player_error_count': errorCount,
      };
}

Future<Map<String, Object?>> observeQaPlayback({
  required Duration window,
  required Duration remainingBudget,
  required QaPlaybackState Function() read,
  required bool Function() isCancelled,
  Future<void> Function(Duration)? wait,
  Duration Function()? elapsed,
}) async {
  if (window < const Duration(seconds: 10) ||
      window > const Duration(seconds: 15)) {
    throw const FormatException(
        'QA playback observation requires 10..15 seconds');
  }
  final clock = Stopwatch()..start();
  final now = elapsed ?? () => clock.elapsed;
  final sleep = wait ?? (delay) => Future<void>.delayed(delay);
  final limit = remainingBudget < window ? remainingBudget : window;
  final samples = <Map<String, Object>>[];
  var cancelled = false;
  // One initial sample plus at most 30 half-second samples, even with bad clocks.
  for (var i = 0; i <= 30 && limit > Duration.zero; i++) {
    if (isCancelled()) {
      cancelled = true;
      break;
    }
    samples.add(read().record(now().inMilliseconds));
    final left = limit - now();
    if (left <= Duration.zero) break;
    await sleep(left < const Duration(milliseconds: 500)
        ? left
        : const Duration(milliseconds: 500));
  }
  final delta = samples.length < 2
      ? null
      : (samples.last['position_ms'] as int) -
          (samples.first['position_ms'] as int);
  return {
    'requested_window_ms': window.inMilliseconds,
    'budget_limited': remainingBudget < window,
    'observed_ms': now().inMilliseconds,
    'cancelled': cancelled,
    'position_delta_ms': delta,
    'frame_evidence':
        'native first frame observed before sampling; continuous frame count unavailable',
    'samples': samples,
  };
}
