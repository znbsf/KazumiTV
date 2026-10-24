import 'package:flutter_test/flutter_test.dart';
import '../tools/qa/source_batch/playback_observation.dart';

void main() {
  test('observation is opt-in and rejects unbounded or wrong-type windows', () {
    expect(qaPlaybackObservationWindow(null), isNull);
    expect(qaPlaybackObservationWindow(15), const Duration(seconds: 15));
    for (final value in [2, 16, 999, '15', true]) {
      expect(() => qaPlaybackObservationWindow(value), throwsFormatException);
    }
  });
  Future<Map<String, Object?>> sample(
      {bool delayed = false,
      bool paused = false,
      bool cancel = false,
      Duration budget = const Duration(seconds: 15)}) {
    var time = Duration.zero;
    return observeQaPlayback(
        window: const Duration(seconds: 15),
        remainingBudget: budget,
        elapsed: () => time,
        wait: (delay) async {
          time += delay;
        },
        isCancelled: () => cancel && time.inSeconds >= 2,
        read: () => QaPlaybackState(
            positionMs:
                delayed && time.inSeconds >= 4 ? time.inMilliseconds - 4000 : 0,
            playing: !paused,
            buffering: !paused && time.inSeconds < 4,
            completed: false,
            bufferMs: time.inMilliseconds,
            durationMs: 60000,
            errorCount: 0));
  }

  test(
      'long window distinguishes delayed startup from the old zero-progress sample',
      () async {
    final result = await sample(delayed: true);
    final rows = result['samples'] as List;
    expect(rows[4]['position_ms'], 0);
    expect(rows.first['buffering'], true);
    expect(rows.last['buffering'], false);
    expect(result['position_delta_ms'], 11000);
    expect(result['observed_ms'], 15000);
    expect(rows.length, 31);
  });
  test(
      'paused and non-advancing playing remain distinguishable without controlling player',
      () async {
    final paused = await sample(paused: true);
    final stalled = await sample();
    expect(paused['position_delta_ms'], 0);
    expect(stalled['position_delta_ms'], 0);
    expect((paused['samples'] as List).last['playing'], false);
    expect((stalled['samples'] as List).last['playing'], true);
  });
  test('shared remaining budget truncates rather than extends the attempt',
      () async {
    final result = await sample(budget: const Duration(seconds: 3));
    expect(result['budget_limited'], true);
    expect(result['observed_ms'], 3000);
  });
  test('cancel stops sampling without accepting late state', () async {
    final result = await sample(cancel: true);
    expect(result['cancelled'], true);
    expect((result['samples'] as List).last['elapsed_ms'], 1500);
  });
  test('exhausted outer budget does not read player state or wait', () async {
    final result = await observeQaPlayback(
        window: const Duration(seconds: 15),
        remainingBudget: Duration.zero,
        isCancelled: () => false,
        read: () => throw StateError('must not read'),
        wait: (_) => throw StateError('must not wait'));
    expect(result['samples'], isEmpty);
    expect(result['position_delta_ms'], isNull);
    expect(result['budget_limited'], true);
  });
}
