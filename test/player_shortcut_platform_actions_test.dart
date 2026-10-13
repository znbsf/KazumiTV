import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/player_shortcut_platform_actions.dart';

void main() {
  test('Android TV non-fullscreen shortcut never invokes desktop window plugin',
      () async {
    var paused = false;
    await dispatchShortcutExitFullscreen(
        fullscreen: false,
        tablet: false,
        desktop: false,
        macOS: false,
        exitFullscreen: () {},
        pause: () {
          paused = true;
        },
        hideWindow: () =>
            throw StateError('No window_manager plugin on Android'));
    expect(paused, false);
  });
  test(
      'fullscreen exit and supported desktop hide execute real injected operations',
      () async {
    final calls = <String>[];
    Future<void> execute(
            {required bool fullscreen,
            required bool desktop,
            bool macOS = false}) =>
        dispatchShortcutExitFullscreen(
            fullscreen: fullscreen,
            tablet: false,
            desktop: desktop,
            macOS: macOS,
            exitFullscreen: () => calls.add('exit'),
            pause: () => calls.add('pause'),
            hideWindow: () => calls.add('hide'));
    await execute(fullscreen: true, desktop: false);
    expect(calls, ['exit']);
    calls.clear();
    await execute(fullscreen: false, desktop: true);
    expect(calls, ['pause', 'hide']);
    calls.clear();
    await execute(fullscreen: false, desktop: true, macOS: true);
    expect(calls, isEmpty);
  });
}
