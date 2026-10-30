// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';

import 'package:kazumi/services/logging/logger.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mobx/mobx.dart';

part 'player_debug_controller.g.dart';

class PlayerDebugController = _PlayerDebugController
    with _$PlayerDebugController;

abstract class _PlayerDebugController with Store {
  /// LogLevel 0: 错误 1: 警告 2: 简略 3: 详细
  int playerLogLevel = 2;

  @observable
  ObservableList<String> playerLog = ObservableList.of([]);
  static const maxLogEntries = 500;
  static const maxLogCharacters = 256 * 1024;
  int _logCharacters = 0;
  final ListQueue<PlayerLog> _rawLogs = ListQueue<PlayerLog>();
  int _rawLogCharacters = 0;
  int _logViewerCount = 0;

  @visibleForTesting
  int get retainedRawLogCharacters => _rawLogCharacters;

  @visibleForTesting
  int get retainedRawLogCount => _rawLogs.length;

  static int _rawSize(PlayerLog event) =>
      event.prefix.length + event.level.length + event.text.length;

  static String _truncate(String value, int limit) {
    if (value.length <= limit) return value;
    const suffix = '…[truncated]';
    return '${value.substring(0, limit - suffix.length)}$suffix';
  }

  static PlayerLog _boundedLog(PlayerLog event) {
    if (_rawSize(event) <= 4096) return event;
    final prefix = _truncate(event.prefix, 256);
    final level = _truncate(event.level, 32);
    return PlayerLog(
      prefix: prefix,
      level: level,
      text: _truncate(event.text, 4096 - prefix.length - level.length),
    );
  }

  void recordLog(PlayerLog event, {required bool playerDebugMode}) {
    final retained = _boundedLog(event);
    _rawLogs.addLast(retained);
    _rawLogCharacters += _rawSize(retained);
    while (_rawLogs.length > maxLogEntries ||
        _rawLogCharacters > maxLogCharacters) {
      _rawLogCharacters -= _rawSize(_rawLogs.removeFirst());
    }
    if (!playerDebugMode && _logViewerCount == 0) return;
    final message = event.toString();
    appendLog(message);
    if (playerDebugMode) {
      KazumiLogger().i("MPV: $message", forceLog: true);
    }
  }

  void attachLogViewer() {
    if (_logViewerCount++ > 0) return;
    // Rebuild from the latest raw window, including events received while the
    // viewer was closed. Reopening must not duplicate already formatted logs.
    runInAction(() {
      playerLog.clear();
      _logCharacters = 0;
      for (final event in _rawLogs) {
        appendLog(event.toString());
      }
    });
  }

  void detachLogViewer() {
    if (_logViewerCount > 0) _logViewerCount--;
  }

  void clearLogs() {
    _rawLogs.clear();
    _rawLogCharacters = 0;
    runInAction(() {
      playerLog.clear();
      _logCharacters = 0;
    });
  }

  void appendLog(String message) {
    runInAction(() {
      if (playerLog.isEmpty) _logCharacters = 0;
      final line = message.length > 4096
          ? '${message.substring(0, 4096)}…[truncated]'
          : message;
      playerLog.add(line);
      _logCharacters += line.length;
      while (playerLog.length > maxLogEntries ||
          _logCharacters > maxLogCharacters) {
        _logCharacters -= playerLog.removeAt(0).length;
      }
    });
  }

  @observable
  int playerWidth = 0;
  @observable
  int playerHeight = 0;
  @observable
  String playerVideoParams = '';
  @observable
  String playerAudioParams = '';
  @observable
  String playerPlaylist = '';
  @observable
  String playerAudioTracks = '';
  @observable
  String playerVideoTracks = '';
  @observable
  String playerAudioBitrate = '';
  @observable
  String playerVideoBitrate = '';

  StreamSubscription<PlayerLog>? playerLogSubscription;
  StreamSubscription<int?>? playerWidthSubscription;
  StreamSubscription<int?>? playerHeightSubscription;
  StreamSubscription<VideoParams>? playerVideoParamsSubscription;
  StreamSubscription<AudioParams>? playerAudioParamsSubscription;
  StreamSubscription<Playlist>? playerPlaylistSubscription;
  StreamSubscription<Track>? playerTracksSubscription;
  StreamSubscription<double?>? playerAudioBitrateSubscription;
  StreamSubscription<double?>? playerVideoBitrateSubscription;

  Future<void> setup(
    Player player, {
    required bool Function(Player player) isCurrentPlayer,
    required bool playerDebugMode,
  }) async {
    await playerLogSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerLogSubscription = player.stream.log.listen((event) {
      if (!isCurrentPlayer(player)) return;
      recordLog(event, playerDebugMode: playerDebugMode);
    });
    await playerWidthSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerWidthSubscription = player.stream.width.listen((event) {
      if (!isCurrentPlayer(player)) return;
      playerWidth = event ?? 0;
    });
    await playerHeightSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerHeightSubscription = player.stream.height.listen((event) {
      if (!isCurrentPlayer(player)) return;
      playerHeight = event ?? 0;
    });
    await playerVideoParamsSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerVideoParamsSubscription = player.stream.videoParams.listen((event) {
      if (!isCurrentPlayer(player)) return;
      playerVideoParams = event.toString();
    });
    await playerAudioParamsSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerAudioParamsSubscription = player.stream.audioParams.listen((event) {
      if (!isCurrentPlayer(player)) return;
      playerAudioParams = event.toString();
    });
    await playerPlaylistSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerPlaylistSubscription = player.stream.playlist.listen((event) {
      if (!isCurrentPlayer(player)) return;
      playerPlaylist = event.toString();
    });
    await playerTracksSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerTracksSubscription = player.stream.track.listen((event) {
      if (!isCurrentPlayer(player)) return;
      playerAudioTracks = event.audio.toString();
      playerVideoTracks = event.video.toString();
    });
    await playerAudioBitrateSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerAudioBitrateSubscription = player.stream.audioBitrate.listen((event) {
      if (!isCurrentPlayer(player)) return;
      playerAudioBitrate = event.toString();
    });
    await playerVideoBitrateSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerVideoBitrateSubscription = player.stream.videoBitrate.listen((event) {
      if (!isCurrentPlayer(player)) return;
      playerVideoBitrate = event.toString();
    });
  }

  Future<void> cancel() async {
    // Detach fields before awaiting so a new player cannot lose its listeners.
    final logSubscription = playerLogSubscription;
    final widthSubscription = playerWidthSubscription;
    final heightSubscription = playerHeightSubscription;
    final videoParamsSubscription = playerVideoParamsSubscription;
    final audioParamsSubscription = playerAudioParamsSubscription;
    final playlistSubscription = playerPlaylistSubscription;
    final tracksSubscription = playerTracksSubscription;
    final audioBitrateSubscription = playerAudioBitrateSubscription;
    final videoBitrateSubscription = playerVideoBitrateSubscription;

    playerLogSubscription = null;
    playerWidthSubscription = null;
    playerHeightSubscription = null;
    playerVideoParamsSubscription = null;
    playerAudioParamsSubscription = null;
    playerPlaylistSubscription = null;
    playerTracksSubscription = null;
    playerAudioBitrateSubscription = null;
    playerVideoBitrateSubscription = null;

    await logSubscription?.cancel();
    await widthSubscription?.cancel();
    await heightSubscription?.cancel();
    await videoParamsSubscription?.cancel();
    await audioParamsSubscription?.cancel();
    await playlistSubscription?.cancel();
    await tracksSubscription?.cancel();
    await audioBitrateSubscription?.cancel();
    await videoBitrateSubscription?.cancel();
  }
}
