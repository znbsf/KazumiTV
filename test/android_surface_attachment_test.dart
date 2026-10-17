import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/surface_attachment.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/first_frame_signal.dart';

void main() {
  test('only explicit direct preattaches; GPU copy/software retain old setup',
      () {
    for (final output in ['gpu', 'gpu-next', null]) {
      for (final delayed in [true, false, null]) {
        expect(
            preattachAndroidSurface(
                output: output, attachAfterVideoParameters: delayed),
            isFalse);
      }
    }
    expect(
        preattachAndroidSurface(
            output: 'mediacodec_embed', attachAfterVideoParameters: false),
        isTrue);
    for (final delayed in [true, null]) {
      expect(
          preattachAndroidSurface(
              output: 'mediacodec_embed', attachAfterVideoParameters: delayed),
          isFalse);
    }
  });

  test('request accepted is not wid installed or first frame', () async {
    final gate = AndroidSurfaceAttachment();
    final frame = AndroidFirstFrameSignal(token: 'new', supported: true);
    var finished = false;
    var rendered = false;
    frame.future.then((_) => rendered = true);
    final task = gate.attach(() async {}, isActive: () => true)
      ..then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    gate.markInstalled();
    await task;
    expect(finished, isTrue);
    expect(rendered, isFalse);
    frame.notify('new');
    await frame.future;
  });

  test('retired output cancels wait and cannot authorize newer output',
      () async {
    final old = AndroidSurfaceAttachment();
    final next = AndroidSurfaceAttachment();
    var active = true;
    final task = old.attach(() async {}, isActive: () => active);
    final assertion = expectLater(task, throwsStateError);
    active = false;
    old.cancel();
    old.markInstalled();
    await assertion;
    expect(next.installed, isFalse);
  });

  test('wid install error fails initialization promptly', () async {
    final gate = AndroidSurfaceAttachment();
    final task = gate.attach(() async {}, isActive: () => true);
    final assertion = expectLater(task, throwsA(isA<ArgumentError>()));
    expect(gate.fail(ArgumentError('native property'), StackTrace.current),
        isTrue);
    await assertion;
  });

  test('missing callback is bounded, not a codec diagnosis', () async {
    final gate = AndroidSurfaceAttachment();
    await expectLater(
        gate.attach(() async {},
            isActive: () => true, timeout: const Duration(milliseconds: 5)),
        throwsA(isA<TimeoutException>()));
  });

  test('cancel interrupts a pending platform request, ignoring its late result',
      () async {
    final old = AndroidSurfaceAttachment();
    final pendingRequest = Completer<void>();
    var active = true;
    final task = old.attach(() => pendingRequest.future,
        isActive: () => active, timeout: const Duration(seconds: 1));
    final assertion = expectLater(
        task.timeout(const Duration(milliseconds: 50)), throwsStateError);
    active = false;
    old.cancel();
    await assertion;
    pendingRequest.complete();
    old.markInstalled();
    final next = AndroidSurfaceAttachment();
    expect(next.installed, isFalse);
  });

  test('platform request itself is included in attachment deadline', () async {
    final gate = AndroidSurfaceAttachment();
    final pendingRequest = Completer<void>();
    final task = gate.attach(() => pendingRequest.future,
        isActive: () => true, timeout: const Duration(milliseconds: 5));
    gate.markInstalled();
    await expectLater(
        task.timeout(const Duration(milliseconds: 50)),
        throwsA(isA<TimeoutException>().having((error) => error.duration,
            'attachment deadline', const Duration(milliseconds: 5))));
    pendingRequest.complete();
  });
}
