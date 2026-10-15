import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/utils/async_rate_limiter.dart';

void main() {
  group('AsyncRateLimiter', () {
    test('first acquire completes immediately without unnecessary delay',
        () async {
      final clock = _ControlledClock();
      final limiter = clock.limiter();
      await limiter.acquire();
      expect(clock.waits, isEmpty);
    });

    test('serial sequential calls maintain at least period spacing', () async {
      const period = Duration(milliseconds: 40);
      final limiter = AsyncRateLimiter(period);

      final timestamps = <int>[];
      final stopwatch = Stopwatch()..start();

      for (var i = 0; i < 3; i++) {
        await limiter.acquire();
        timestamps.add(stopwatch.elapsedMilliseconds);
      }

      expect(timestamps.length, 3);
      for (var i = 1; i < timestamps.length; i++) {
        final diff = timestamps[i] - timestamps[i - 1];
        expect(diff, greaterThanOrEqualTo(35));
      }
    });

    test('concurrent callers are spaced apart into sequential time slots',
        () async {
      const period = Duration(milliseconds: 40);
      final limiter = AsyncRateLimiter(period);

      final completionTimes = <int>[];
      final stopwatch = Stopwatch()..start();

      await Future.wait(
        List.generate(4, (index) async {
          await limiter.acquire();
          completionTimes.add(stopwatch.elapsedMilliseconds);
        }),
      );

      expect(completionTimes.length, 4);
      for (var i = 1; i < completionTimes.length; i++) {
        final diff = completionTimes[i] - completionTimes[i - 1];
        expect(diff, greaterThanOrEqualTo(35));
      }
    });

    test('run passes return value and preserves rate limit on failure',
        () async {
      const period = Duration(milliseconds: 40);
      final limiter = AsyncRateLimiter(period);

      final stopwatch = Stopwatch()..start();

      final firstResult = await limiter.run(() async => 'success');
      expect(firstResult, 'success');

      await expectLater(
        limiter.run(() async => throw StateError('action error')),
        throwsStateError,
      );

      final secondResult = await limiter.run(() async => 'recovered');
      expect(secondResult, 'recovered');

      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(70));
    });
  });

  test('an early timer wake cannot grant a slot before the deadline', () async {
    final clock = _ControlledClock();
    final limiter = clock.limiter();
    await limiter.acquire();
    var granted = false;
    final second = limiter.acquire().then((_) => granted = true);
    await Future<void>.delayed(Duration.zero);
    await clock.wakeAllAt(33);
    expect(granted, isFalse);
    expect(clock.waits.single, const Duration(milliseconds: 7));
    await clock.wakeAllAt(40);
    await second;
    expect(granted, isTrue);
  });

  test('late timers do not release queued callers in a catch-up burst',
      () async {
    final clock = _ControlledClock();
    final limiter = clock.limiter();
    final grants = <int>[];
    Future<void> acquire() async {
      await limiter.acquire();
      grants.add(clock.now.inMilliseconds);
    }

    await acquire();
    final second = acquire();
    final third = acquire();
    await Future<void>.delayed(Duration.zero);
    await clock.wakeAllAt(100);
    expect(grants, [0, 100]);
    expect(clock.waits.single, const Duration(milliseconds: 40));
    await clock.wakeAllAt(140);
    await Future.wait([second, third]);
    expect(grants, [0, 100, 140]);
  });
}

class _ControlledClock {
  Duration now = Duration.zero;
  final waits = <Duration>[];
  final pending = <Completer<void>>[];
  AsyncRateLimiter limiter() =>
      AsyncRateLimiter(const Duration(milliseconds: 40),
          elapsed: () => now,
          delay: (duration) {
            waits.add(duration);
            final completer = Completer<void>();
            pending.add(completer);
            return completer.future;
          });
  Future<void> wakeAllAt(int milliseconds) async {
    now = Duration(milliseconds: milliseconds);
    final due = List<Completer<void>>.of(pending);
    pending.clear();
    waits.clear();
    for (final completer in due) {
      completer.complete();
    }
    await Future<void>.delayed(Duration.zero);
  }
}
