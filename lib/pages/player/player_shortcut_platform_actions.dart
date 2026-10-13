import 'dart:async';

/// Platform operations are injected so non-desktop shortcuts cannot accidentally
/// invoke an unsupported desktop window plugin.
Future<void> dispatchShortcutExitFullscreen({
  required bool fullscreen,
  required bool tablet,
  required bool desktop,
  required bool macOS,
  required FutureOr<void> Function() exitFullscreen,
  required FutureOr<void> Function() pause,
  required FutureOr<void> Function() hideWindow,
}) async {
  if (fullscreen && !tablet) {
    await exitFullscreen();
  } else if (desktop && !macOS) {
    await pause();
    await hideWindow();
  }
}
