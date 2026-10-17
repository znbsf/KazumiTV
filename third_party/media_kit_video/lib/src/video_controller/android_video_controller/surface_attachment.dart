import 'dart:async';

/// Surface availability is separate from an actual rendered video frame.
class AndroidSurfaceAttachment {
  final _ready = Completer<void>();
  final _cancelled = Completer<void>();
  bool installed = false;
  bool _waiting = false;

  Future<void> attach(Future<void> Function() request,
      {required bool Function() isActive,
      Duration timeout = const Duration(seconds: 10)}) async {
    _waiting = true;
    try {
      // Bound both the platform request and the installed-property callback.
      // Cancellation must not wait for a platform reply that may never arrive.
      await Future.any<void>([
        Future.wait<void>([Future<void>.sync(request), _ready.future],
            eagerError: true),
        _cancelled.future.then<void>((_) {
          throw StateError('Video output retired before Surface attachment');
        }),
      ]).timeout(timeout);
      if (!isActive() || !installed) {
        throw StateError('Video output retired before Surface attachment');
      }
    } finally {
      _waiting = false;
    }
  }

  void markInstalled() {
    installed = true;
    if (!_ready.isCompleted) _ready.complete();
  }

  bool fail(Object error, StackTrace stack) {
    if (!_waiting || _ready.isCompleted) return false;
    _ready.completeError(error, stack);
    return true;
  }

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// Only direct MediaCodec needs a Surface before decoding starts. GPU routes
/// retain their established dimensions-first setup, including copy and software.
bool preattachAndroidSurface(
        {required String? output, required bool? attachAfterVideoParameters}) =>
    output == 'mediacodec_embed' && attachAfterVideoParameters == false;
