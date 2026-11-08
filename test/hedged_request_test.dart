import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/utils/hedged_request.dart';

void main() {
  void scenario(void Function(FakeAsync, _Race) body) {
    fakeAsync((clock) {
      final race = _Race();
      body(clock, race);
      expect(clock.pendingTimers.length, 0, reason: 'no hedge timer survives');
    });
  }

  test('fast primary never starts backup, including an empty success', () {
    scenario((clock, race) {
      race.primary.complete('');
      clock.flushMicrotasks();
      expect(race.result?.value, '');
      expect(clock.pendingTimers, isEmpty);
      clock.elapse(const Duration(seconds: 10));
      expect(race.backupCalls, 0);
    });
  });

  test('backup starts only at delay, wins and cancels primary', () {
    scenario((clock, race) {
      clock.elapse(const Duration(seconds: 3));
      expect(race.backupCalls, 0);
      clock.elapse(const Duration(seconds: 1));
      expect(race.backupCalls, 1);
      race.backup.complete('backup');
      clock.flushMicrotasks();
      expect(race.result?.fromBackup, isTrue);
      expect(race.primaryToken.isCancelled, isTrue);
      expect(race.backupToken!.isCancelled, isFalse);
      race.primary.complete('late primary');
      clock.flushMicrotasks();
      expect(race.result?.value, 'backup');
    });
  });

  for (final lateError in [false, true]) {
    test('primary wins after delay; late backup error=$lateError is inert', () {
      scenario((clock, race) {
        clock.elapse(catalogueHedgeDelay);
        race.primary.complete('primary');
        clock.flushMicrotasks();
        expect(race.result?.fromBackup, isFalse);
        expect(race.backupToken!.isCancelled, isTrue);
        if (lateError) {
          race.backup.completeError(StateError('late'));
        } else {
          race.backup.complete('late backup');
        }
        clock.flushMicrotasks();
        expect(race.result?.value, 'primary');
        expect(race.completions, 1);
      });
    });
  }

  for (final empty in [false, true]) {
    test('backup empty=$empty cannot beat pending primary', () {
      scenario((clock, race) {
        clock.elapse(catalogueHedgeDelay);
        if (empty) {
          race.backup.complete('');
        } else {
          race.backup.completeError(StateError('backup failed'));
        }
        clock.flushMicrotasks();
        expect(race.completions, 0);
        race.primary.complete('primary');
        clock.flushMicrotasks();
        expect(race.result?.value, 'primary');
      });
    });
  }

  test('retryable early failure starts backup immediately and exactly once',
      () {
    scenario((clock, race) {
      race.primary.completeError(const FormatException('retryable'));
      clock.flushMicrotasks();
      expect(race.backupCalls, 1);
      clock.elapse(const Duration(seconds: 10));
      expect(race.backupCalls, 1);
      race.backup.complete('backup');
      clock.flushMicrotasks();
      expect(race.result?.value, 'backup');
    });
  });

  test('primary failure while backup runs waits even if non-retryable', () {
    scenario((clock, race) {
      clock.elapse(catalogueHedgeDelay);
      race.primary.completeError(StateError('non-retryable'));
      clock.flushMicrotasks();
      expect(race.completions, 0);
      race.backup.complete('backup');
      clock.flushMicrotasks();
      expect(race.result?.value, 'backup');
    });
  });

  for (final backupFirst in [false, true]) {
    test('both fail, backup first=$backupFirst, returns null once', () {
      scenario((clock, race) {
        if (backupFirst) {
          clock.elapse(catalogueHedgeDelay);
          race.backup.completeError(StateError('failed'));
          clock.flushMicrotasks();
        }
        race.primary.completeError(const FormatException('failed'));
        clock.flushMicrotasks();
        if (!backupFirst) race.backup.completeError(StateError('failed'));
        clock.flushMicrotasks();
        expect(race.result, isNull);
        expect(race.completions, 1);
        clock.elapse(const Duration(seconds: 10));
        expect(race.backupCalls, 1);
      });
    });
  }

  test('early non-retryable failure never starts backup', () {
    scenario((clock, race) {
      race.primary.completeError(StateError('failed'));
      clock.flushMicrotasks();
      expect(race.completions, 1);
      expect(race.result, isNull);
      expect(clock.pendingTimers, isEmpty);
      clock.elapse(const Duration(seconds: 10));
      expect(race.backupCalls, 0);
    });
  });

  test('synchronous primary and backup throws are observed', () {
    fakeAsync((clock) {
      var done = false;
      hedgedRequest<String>(
        primary: (_) => throw const FormatException(),
        backup: (_) => throw StateError('failed'),
        canRetry: (_) => true,
        acceptBackup: (_) => true,
      ).then((value) {
        expect(value, isNull);
        done = true;
      });
      clock.flushMicrotasks();
      expect(done, isTrue);
      expect(clock.pendingTimers.length, 0);
    });
  });
}

class _Race {
  _Race() {
    hedgedRequest<String>(
      primary: (token) {
        primaryToken = token;
        return primary.future;
      },
      backup: (token) {
        backupCalls++;
        backupToken = token;
        return backup.future;
      },
      canRetry: (error) => error is FormatException,
      acceptBackup: (value) => value.isNotEmpty,
    ).then((value) {
      result = value;
      completions++;
    });
  }

  final primary = Completer<String>();
  final backup = Completer<String>();
  late CancelToken primaryToken;
  CancelToken? backupToken;
  int backupCalls = 0;
  int completions = 0;
  HedgedResult<String>? result;
}
