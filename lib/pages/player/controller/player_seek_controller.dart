import 'dart:async';
import 'package:media_kit/media_kit.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'package:kazumi/pages/player/controller/player_playback_controller.dart';

class _InteractiveSeekSession {
  _InteractiveSeekSession(this.pauseCompleted, this.target);

  final Future<void> pauseCompleted;
  Duration target;
  Future<bool>? commit;
}

class _SeekRequest {
  _SeekRequest(this.player, this.target, this.enableSync);
  final Player player;
  Duration target;
  bool enableSync;
  final completed = Completer<void>();
}

class PlayerSeekController {
  PlayerSeekController({
    required PlayerPlaybackController playback,
    required PlayerDanmakuController danmaku,
    required Future<void> Function({bool enableSync}) pause,
    required Future<void> Function({bool enableSync}) play,
    required Future<void> Function(bool enableSync) onSeekCompleted,
  })  : _playback = playback,
        _danmaku = danmaku,
        _pause = pause,
        _play = play,
        _onSeekCompleted = onSeekCompleted;

  final PlayerPlaybackController _playback;
  final PlayerDanmakuController _danmaku;
  final Future<void> Function({bool enableSync}) _pause;
  final Future<void> Function({bool enableSync}) _play;
  final Future<void> Function(bool enableSync) _onSeekCompleted;

  _SeekRequest? _activeSeek;
  _SeekRequest? _pendingSeek;
  _InteractiveSeekSession? _interactiveSession;

  bool get hasActiveInteractiveSeek => _interactiveSession != null;

  Future<void> seekTo(
    Duration target, {
    bool enableSync = true,
  }) {
    final player = _playback.mediaPlayer;
    if (player == null) {
      return Future<void>.value();
    }

    final normalizedTarget = _normalize(target);
    _playback.currentPosition = normalizedTarget;
    _danmaku.clearAndInvalidateScheduledDanmakus();

    if (_activeSeek?.player == player) {
      final pending =
          _pendingSeek ??= _SeekRequest(player, normalizedTarget, enableSync);
      pending.target = normalizedTarget;
      pending.enableSync = enableSync;
      return pending.completed.future;
    }

    // A replacement player must not wait for an old native seek to return.
    _pendingSeek?.completed.complete();
    _pendingSeek = null;
    final request = _SeekRequest(player, normalizedTarget, enableSync);
    _activeSeek = request;
    unawaited(_runSeek(request));
    return request.completed.future;
  }

  Future<void> _runSeek(_SeekRequest request) async {
    try {
      if (!_playback.isCurrentPlayer(request.player)) return;
      try {
        await request.player.seek(request.target);
      } catch (_) {
        return;
      }
      // An obsolete intermediate target must not broadcast the newer UI
      // position before the native player has actually sought to it.
      if (_playback.isCurrentPlayer(request.player) && _pendingSeek == null) {
        await _onSeekCompleted(request.enableSync);
      }
    } catch (error, stack) {
      request.completed.completeError(error, stack);
    } finally {
      if (!request.completed.isCompleted) request.completed.complete();
      if (identical(_activeSeek, request)) {
        final next = _pendingSeek;
        _pendingSeek = null;
        _activeSeek = next;
        if (next != null) unawaited(_runSeek(next));
      }
    }
  }

  Future<void> seekBy(
    Duration offset, {
    bool enableSync = true,
  }) =>
      seekTo(
        _playback.currentPosition + offset,
        enableSync: enableSync,
      );

  void beginInteractiveSeek() {
    _interactiveSession = _InteractiveSeekSession(
      _pause(enableSync: false),
      _playback.currentPosition,
    );
  }

  bool updateInteractiveSeek(Duration target) {
    final session = _interactiveSession;
    if (session == null) {
      return false;
    }
    session.target = _normalize(target);
    _playback.currentPosition = session.target;
    return true;
  }

  Future<bool> commitInteractiveSeek() {
    final session = _interactiveSession;
    if (session == null) {
      return Future<bool>.value(false);
    }
    return session.commit ??= _commitInteractiveSeek(session);
  }

  void invalidateInteractiveSeek() {
    _interactiveSession = null;
  }

  Future<bool> _commitInteractiveSeek(
    _InteractiveSeekSession session,
  ) async {
    try {
      await session.pauseCompleted;
      if (!_isCurrent(session)) {
        return false;
      }

      await seekTo(session.target);
      if (!_isCurrent(session)) {
        return false;
      }

      await _play(enableSync: false);
      return _isCurrent(session);
    } finally {
      if (_isCurrent(session)) {
        _interactiveSession = null;
      }
    }
  }

  Duration _normalize(Duration target) {
    var milliseconds = target.inMilliseconds;
    if (milliseconds < 0) {
      milliseconds = 0;
    }
    final duration = _playback.duration;
    if (duration > Duration.zero && milliseconds > duration.inMilliseconds) {
      milliseconds = duration.inMilliseconds;
    }
    return Duration(milliseconds: milliseconds);
  }

  bool _isCurrent(_InteractiveSeekSession session) =>
      identical(_interactiveSession, session);
}
