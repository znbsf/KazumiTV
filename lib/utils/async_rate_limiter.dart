import 'dart:async';

/// Ensures asynchronous operations are spaced apart by at least a minimum interval.
class AsyncRateLimiter {
  AsyncRateLimiter(this.period,
      {Duration Function()? elapsed, Future<void> Function(Duration)? delay})
      : _elapsed = elapsed ?? _monotonicClock(),
        _delay = delay ?? Future<void>.delayed;

  static Duration Function() _monotonicClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  final Duration Function() _elapsed;
  final Future<void> Function(Duration) _delay;

  final Duration period;
  Duration? _lastGranted;
  Future<void> _tail = Future<void>.value();

  /// Serializes grants, not actions. Late wakeups must not create catch-up bursts.
  Future<void> acquire() {
    final granted = _tail.then((_) async {
      final previous = _lastGranted;
      if (previous != null) {
        var remaining = period - (_elapsed() - previous);
        while (remaining > Duration.zero) {
          // Timers use millisecond granularity. Round up rather than spinning
          // through zero-delay timers for a positive sub-millisecond remainder.
          await _delay(
              Duration(milliseconds: (remaining.inMicroseconds + 999) ~/ 1000));
          // Timer precision and elapsed-time precision may differ.
          remaining = period - (_elapsed() - previous);
        }
      }
      _lastGranted = _elapsed();
    });
    // Keep future callers usable even if an injected/platform delay fails.
    _tail = granted.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return granted;
  }

  /// Runs [action] after acquiring a rate-limited time slot.
  Future<T> run<T>(Future<T> Function() action) async {
    await acquire();
    return await action();
  }
}
