# KazumiTV Android consumed-frame patch

Source: Predidit/media-kit, fixed revision
`994465d9bfca3f39d0b41199d16e7fd93fe97881`, package `media_kit_video` 1.2.5.
Imported from the existing local package snapshot; original MIT LICENSE retained.
No libmpv binaries or shared Pub cache files are changed. Example and monorepo
`pubspec_overrides.yaml` are omitted; `media_kit` resolves to the application's
same fixed Git dependency instead of the monorepo sibling path.

## Evidence semantics

Android previously completed `waitUntilFirstFrameRendered` on video dimensions.
This patch completes an independent signal only after SurfaceTexture's
`setOnFrameConsumedListener` callback. The listener is armed after nonzero video
dimensions, rejects timestamp zero and the already-consumed buffer at arming,
and notifies once. Creation only creates a Surface; it never draws or queues an
initial placeholder buffer. Dimensions and `onSurfaceAvailable` never complete
the signal. Zero-PTS first frames conservatively wait for the next buffer.

Callbacks cross to the main thread and carry an output-instance token. Disposal
retires the gate and removes the listener; Dart ignores wrong tokens, retired
outputs and duplicates. The raster callback avoids the VideoOutput lock to
prevent a lock inversion against Flutter's texture wrapper during release.

SurfaceProducer has no equivalent public consumption callback; its first-frame
Future intentionally remains pending, so bounded callers report unconfirmed
instead of success. KazumiTV's tested path configures SurfaceTexture (`false`).
The Future retains one-output-lifetime semantics, not per-media/open semantics.
Source-health creates a fresh Player/controller for each candidate.

This proves Flutter consumed a submitted image, not that a human saw meaningful
content, that playback keeps advancing, or that audio is synchronized. Device
visual/AV acceptance remains required.

## API verification and tests

Read-only verification used local Flutter engine
`af7e796e161ae0bb1ff0758c71a7105418bd9ded` Android embedding with `javap`:
SurfaceTextureEntry exposes the listener; SurfaceTextureWrapper calls it after
`SurfaceTexture.updateTexImage()`.

- https://api.flutter.dev/javadoc/io/flutter/view/TextureRegistry.SurfaceTextureEntry.html
- https://github.com/flutter/flutter/blob/af7e796e161ae0bb1ff0758c71a7105418bd9ded/engine/src/flutter/shell/platform/android/io/flutter/embedding/engine/renderer/SurfaceTextureWrapper.java

Tests supplied but not run by the patch author (build/device ownership stays
with the integration owner):

- From application root: `flutter test third_party/media_kit_video/test/android_first_frame_signal_test.dart`
- Compile FirstFrameGate.java and test/FirstFrameGateTest.java together into a
  temporary output directory with `javac -d <output> ...`, then execute
  `java -cp <output> com.alexmercerind.media_kit_video.FirstFrameGateTest`.
- Native embedding/real-device test: dimensions without submitted frames must
  time out; known video must notify only after consumption; cancel/dispose and
  handle reuse must not complete a later output; SurfaceProducer must remain
  unconfirmed; exercise both software/GPU and mediacodec_embed outputs.

Run application `flutter pub get` to regenerate the lockfile for this path
override before building. Do not claim tests or APK acceptance from source review.
