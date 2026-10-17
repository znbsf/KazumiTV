import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/first_frame_signal.dart';

void main() {
  test('only a matching native consumption notification completes the future', () async {
    final signal = AndroidFirstFrameSignal(token: 'new-output', supported: true);
    var completed = false;
    signal.future.then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse); // texture/controller creation is not a frame
    signal.notify('retired-output');
    signal.notify(null);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    signal.notify('new-output');
    await signal.future;
    expect(completed, isTrue);
    signal.notify('new-output'); // duplicate must not throw
  });

  test('disposed outputs ignore late native notifications', () async {
    final signal = AndroidFirstFrameSignal(token: 'retired', supported: true);
    var completed = false;
    signal.future.then((_) => completed = true);
    signal.dispose();
    signal.notify('retired');
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
  });

  test('unsupported SurfaceProducer never reports success', () async {
    final signal = AndroidFirstFrameSignal(token: 'producer', supported: false);
    var completed = false;
    signal.future.then((_) => completed = true);
    signal.notify('producer');
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
  });
}
