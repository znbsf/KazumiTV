import 'package:kazumi/utils/async_serial_queue.dart';

typedef PlaybackProgressWriter = Future<void> Function(
    Duration position, Duration duration);

/// One recorder per native media session. Inputs must come from native state,
/// never from a requested seek target or a prepared route.
class PlaybackHistoryRecorder {
  PlaybackHistoryRecorder(this._write, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final PlaybackProgressWriter _write;
  final DateTime Function() _now;
  DateTime? _lastPeriodicWrite;
  static const persistenceInterval = Duration(seconds: 5);
  final AsyncSerialQueue _writes = AsyncSerialQueue();
  bool _hasPlayed = false;
  (Duration, Duration)? _saved;

  void observePlaying(bool playing) {
    _hasPlayed |= playing;
  }

  Future<void> record({
    required Duration position,
    required Duration duration,
    required bool playing,
    bool periodic = false,
  }) {
    observePlaying(playing);
    if (!_hasPlayed ||
        duration <= Duration.zero ||
        position < Duration.zero ||
        position > duration) {
      return Future<void>.value();
    }
    final snapshot = (position, duration);
    final now = _now();
    if (periodic &&
        playing &&
        _lastPeriodicWrite != null &&
        now.difference(_lastPeriodicWrite!) < persistenceInterval) {
      return Future<void>.value();
    }
    _lastPeriodicWrite = now;
    return _writes.run(() async {
      if (_saved == snapshot) return;
      try {
        // One write captures both the local progress and its WebDAV events.
        await _write(position, duration);
      } catch (_) {
        _lastPeriodicWrite = null;
        rethrow;
      }
      _saved = snapshot;
    });
  }
}
