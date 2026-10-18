import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/output_lifetime.dart';
import 'package:synchronized/synchronized.dart';

void main() {
  test('dispose retires queued wid work before reading notifiers', () async {
    final lifetime = AndroidOutputLifetime(playerDisposed: () => false);
    final lock = Lock();
    final held = Completer<void>();
    final first = lock.synchronized(() => held.future);
    var readNotifier = false;
    final queued = lock.synchronized(() => lifetime.run(() async {
          readNotifier = true;
        }));
    lifetime.close();
    held.complete();
    await Future.wait([first, queued]);
    expect(readNotifier, isFalse);
  });
  test(
      'native lock rejects queued seek after dispose: only retired assertion is cancellation',
      () async {
    var disposed = false;
    final old = AndroidOutputLifetime(playerDisposed: () => disposed);
    final nativeCommand = Completer<void>();
    final result = old.run(() => nativeCommand.future);
    disposed = true;
    nativeCommand.completeError(AssertionError('[Player] has been disposed'));
    await result;
    var nextFrame = false;
    final next = AndroidOutputLifetime(playerDisposed: () => false);
    await next.run(() async {
      nextFrame = true;
    });
    expect(nextFrame, isTrue);
  });
  test('active disposed assertion and unrelated retired errors propagate',
      () async {
    final active = AndroidOutputLifetime(playerDisposed: () => false);
    await expectLater(active.run(() async {
      throw AssertionError('[Player] has been disposed');
    }), throwsA(isA<AssertionError>()));
    final pending = Completer<void>();
    final running = active.run(() => pending.future);
    active.close();
    final expectation = expectLater(running, throwsStateError);
    pending.completeError(StateError('real output failure'));
    await expectation;
  });
  test('await continuation checks retirement before next command', () async {
    final lifetime = AndroidOutputLifetime(playerDisposed: () => false);
    final property = Completer<void>();
    var seek = false;
    final running = lifetime.run(() async {
      await property.future;
      if (!lifetime.active) return;
      seek = true;
    });
    lifetime.close();
    property.complete();
    await running;
    expect(seek, isFalse);
  });
}
