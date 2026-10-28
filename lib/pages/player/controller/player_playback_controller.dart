// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'package:kazumi/services/logging/playback_trace.dart';
import 'package:kazumi/services/player/current_output_failure.dart';
import 'package:kazumi/pages/player/controller/playback_recovery_snapshot.dart';
import 'package:kazumi/services/player/confirmed_playback_recovery.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/pages/player/controller/player_debug_controller.dart';
import 'package:kazumi/pages/player/controller/player_diagnostics.dart';
import 'package:kazumi/pages/player/controller/player_super_resolution.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/network/proxy_utils.dart';
import 'package:kazumi/services/network/system_proxy_service.dart';
import 'package:kazumi/services/player/playback_cache_policy.dart';
import 'package:kazumi/services/player/playback_history_recorder.dart';
import 'package:kazumi/services/player/android_video_output.dart';
import 'package:kazumi/services/player/player_error_mapper.dart';
import 'package:kazumi/services/player/player_screenshot_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/video_source/video_source_format.dart';
import 'package:kazumi/utils/async_serial_queue.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mobx/mobx.dart';
import 'package:kazumi/utils/device.dart';
import 'package:kazumi/utils/media.dart';
import 'package:kazumi/services/platform/platform_environment_service.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/performance/tv_input_lifecycle.dart';

part 'player_playback_controller.g.dart';

class PlayerPlaybackController = _PlayerPlaybackController
    with _$PlayerPlaybackController;

final class _OwnedPlayer {
  _OwnedPlayer(this.player, PlaybackProgressWriter? writeHistory)
      : history = writeHistory == null
            ? null
            : PlaybackHistoryRecorder(writeHistory) {
    if (history != null) {
      _playingSubscription = player.stream.playing.listen((playing) {
        history!.observePlaying(playing);
        if (!playing) unawaited(recordHistory());
      });
    }
    if (TvInputLifecycle.enabled) {
      // Typed media-kit events only, never a native property query. The
      // optional diagnostic owner cancels this subscription with the player.
      _rateProbeSubscription = player.stream.rate.listen((rate) {
        if (TvInputLifecycle.active)
          TvInputLifecycle.trace('player_rate', {
            'rate': rate,
            'source': 'media_kit_typed_rate_event',
            'playerIdentity': identityHashCode(player),
          });
      });
    }
  }

  final trace = PlaybackTrace('native');
  final Player player;
  final PlaybackHistoryRecorder? history;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<double>? _rateProbeSubscription;
  bool intendedPlaying = false;
  bool hasNativeError = false;
  final recoveryAborted = Completer<void>();
  void abortRecoveryWait() {
    if (!recoveryAborted.isCompleted) recoveryAborted.complete();
  }

  bool ready = false;
  bool released = false;
  final List<StreamSubscription<dynamic>> subscriptions = [];
  Future<void>? _disposeFuture;

  Future<void> recordHistory({bool periodic = false}) async {
    if (!ready || history == null) return;
    try {
      final state = player.state;
      await history!.record(
          position: state.position,
          duration: state.duration,
          playing: state.playing,
          periodic: periodic);
    } catch (error, stackTrace) {
      KazumiLogger().w('Player: failed to save playback progress',
          error: error, stackTrace: stackTrace);
    }
  }

  Future<void> dispose() {
    return _disposeFuture ??= _dispose();
  }

  Future<void> _dispose() async {
    trace.finish('disposed');
    abortRecoveryWait();
    // Capture synchronously before the native player is detached/disposed.
    final finalHistory = recordHistory();
    ready = false;
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await _rateProbeSubscription?.cancel();
    await _playingSubscription?.cancel();
    try {
      await player.dispose();
      released = true;
    } catch (error, stackTrace) {
      KazumiLogger().e(
        'PlayerPlaybackController: failed to dispose media player',
        error: error,
        stackTrace: stackTrace,
      );
      try {
        await player.stop();
      } catch (_) {}
    }
    await finalHistory;
  }
}

abstract class _PlayerPlaybackController with Store {
  _PlayerPlaybackController({
    required this.shaderAssetService,
    required this.debug,
    required this.videoUrl,
    required this.isLocalPlayback,
  });

  final ShaderAssetService shaderAssetService;
  final PlayerDebugController debug;
  final String Function() videoUrl;
  final bool Function() isLocalPlayback;
  final PlayerScreenshotService screenshotService =
      const PlayerScreenshotService();
  late final PlaybackCachePolicy cachePolicy = PlaybackCachePolicy(
    isLocalPlayback: isLocalPlayback,
    currentPlayer: () => mediaPlayer,
  );

  _OwnedPlayer? _ownedPlayer;
  Future<void> _pendingDisposal = Future<void>.value();
  bool _lastReleaseSucceeded = true;
  bool get lastReleaseSucceeded => _lastReleaseSucceeded;
  bool recoveryBlocksCompletion = false;
  bool get recoveryHasNativeError => _ownedPlayer?.hasNativeError ?? false;
  Player? get mediaPlayer => _ownedPlayer?.player;
  Future<void> recordHistory({bool periodic = false}) =>
      _ownedPlayer?.recordHistory(periodic: periodic) ?? Future<void>.value();

  // Native failure/EOF can report paused before the decoder log arrives.
  // Keep explicit playback intent on the owner, separate from observed state.
  void setPlaybackIntent(Player player, bool playing) {
    if (isCurrentPlayer(player)) _ownedPlayer!.intendedPlaying = playing;
  }

  void enableHistoryFor(Player player) {
    if (identical(mediaPlayer, player)) _ownedPlayer!.ready = true;
  }

  final Observable<VideoController?> _videoController = Observable(null);
  VideoController? get videoController => _videoController.value;
  set videoController(VideoController? value) {
    // Initialization and stop() also publish outside generated store actions.
    runInAction(() => _videoController.value = value);
  }

  final AsyncSerialQueue _prefetchWrites = AsyncSerialQueue();
  bool _prefetchSuspendWanted = false;

  bool hAenable = true;
  late String hardwareDecoder;
  bool androidEnableOpenSLES = true;
  bool autoPlay = true;
  bool playerDebugMode = false;
  bool androidEmulator = false;
  int buttonSkipTime = 80;
  int arrowKeySkipTime = 10;

  Future<PlayerDiagnosticsSnapshot> readDiagnostics() async {
    // NativePlayer.getProperty is a synchronous FFI call despite returning a
    // Future. A stalled codec can block the UI isolate before a timeout runs.
    // Use typed event snapshots; unreported native counters remain unknown.
    return PlayerDiagnosticsSnapshot.fromCachedState(
      mediaPlayer?.state ?? const PlayerState(),
      hardwareAccelerationEnabled: hAenable,
      configuredHardwareDecoder: hardwareDecoder,
    );
  }

  /// 历史记录传入的 offset
  int startOffset = 0;

  /// 当前超分辨率模式
  @observable
  SuperResolutionMode superResolutionMode = SuperResolutionMode.off;

  @observable
  double volume = -1;

  /// 手势调节时的精确音量，避免 UI 节流导致累计误差
  double preciseVolume = -1;

  @observable
  bool loading = true;
  @observable
  bool playing = false;
  @observable
  bool isBuffering = true;
  @observable
  bool completed = false;
  @observable
  Duration currentPosition = Duration.zero;
  @observable
  Duration buffer = Duration.zero;
  @observable
  Duration duration = Duration.zero;
  @observable
  double playerSpeed = 1.0;

  bool isCurrentPlayer(Player player) {
    return identical(mediaPlayer, player);
  }

  Future<Player?> _discardIfNotCurrent(_OwnedPlayer candidate) async {
    if (identical(_ownedPlayer, candidate)) {
      return candidate.player;
    }
    await candidate.dispose();
    return null;
  }

  Future<void> _cancelDebugInfo() async {
    try {
      await debug.cancel();
    } catch (_) {}
  }

  @action
  void resetForInit() {
    recoveryBlocksCompletion = false;
    playing = false;
    loading = true;
    isBuffering = true;
    currentPosition = Duration.zero;
    buffer = Duration.zero;
    duration = Duration.zero;
    completed = false;
    startOffset = 0;
  }

  /// 本次会话是否从距结尾 [nearEndWatchedThreshold] 以内的位置起播。
  /// 这样的"播放完成"并非真正看完，应从头重播而非切下一集
  bool get resumedNearEnd {
    if (startOffset <= 0 || duration <= Duration.zero) {
      return false;
    }
    return Duration(seconds: startOffset) >= duration - nearEndWatchedThreshold;
  }

  /// 从头重播当前视频。[startOffset] 在重播落地后才归零，
  /// 避免自动连播在此期间抢先触发
  Future<void> restartFromBeginning() async {
    final player = mediaPlayer;
    if (player == null) {
      return;
    }
    try {
      await player.seek(Duration.zero);
      if (!isCurrentPlayer(player)) {
        return;
      }
      setPlaybackIntent(player, true);
      await player.play();
      startOffset = 0;
    } catch (e) {
      KazumiLogger()
          .w('PlayerController: failed to restart from beginning', error: e);
    }
  }

  bool get playerPlaying {
    try {
      return mediaPlayer?.state.playing ?? false;
    } catch (_) {
      return false;
    }
  }

  bool get playerBuffering {
    try {
      return mediaPlayer?.state.buffering ?? false;
    } catch (_) {
      return false;
    }
  }

  bool get playerCompleted {
    try {
      return mediaPlayer?.state.completed ?? false;
    } catch (_) {
      return false;
    }
  }

  double get playerVolume {
    try {
      return mediaPlayer?.state.volume ?? volume;
    } catch (_) {
      return volume;
    }
  }

  Duration get playerPosition {
    try {
      return mediaPlayer?.state.position ?? currentPosition;
    } catch (_) {
      return currentPosition;
    }
  }

  Duration get playerBuffer {
    try {
      return mediaPlayer?.state.buffer ?? buffer;
    } catch (_) {
      return buffer;
    }
  }

  Duration get playerDuration {
    try {
      return mediaPlayer?.state.duration ?? duration;
    } catch (_) {
      return duration;
    }
  }

  /// Android blocks network access for backgrounded apps; a prefetching
  /// demuxer then burns through ffmpeg's reconnect/segment retries and marks
  /// the stream EOF, leaving playback permanently stuck once foregrounded.
  /// Suspending zeroes the readahead window so no new requests are issued
  /// while buffered data stays available; restore values are mpv defaults,
  /// which media_kit leaves untouched. Writes are serialized and apply the
  /// latest requested state, so rapid lifecycle flips cannot reorder.
  Future<void> setPrefetchSuspended(bool suspended) async {
    if (!Platform.isAndroid) {
      return;
    }
    _prefetchSuspendWanted = suspended;
    await _prefetchWrites.run(() async {
      final wanted = _prefetchSuspendWanted;
      final player = mediaPlayer;
      if (player == null) {
        return;
      }
      try {
        final pp = player.platform as NativePlayer;
        await pp.setProperty('cache-secs', wanted ? '0' : '36000');
        if (!isCurrentPlayer(player)) {
          return;
        }
        await pp.setProperty('demuxer-readahead-secs', wanted ? '0' : '1');
      } catch (e) {
        KazumiLogger().w(
          'PlayerController: failed to ${wanted ? 'suspend' : 'resume'} demuxer prefetch',
          error: e,
        );
      }
    });
  }

  Future<Player?> createVideoController(
    Map<String, String> httpHeaders,
    bool adBlockerEnabled, {
    required bool Function() canInstall,
    int offset = 0,
    PlaybackRecoverySnapshot? recoverySnapshot,
    void Function(PlaybackRecoverySnapshot snapshot)? onDirectDecoderFailure,
    VideoSourceFormat videoSourceFormat = VideoSourceFormat.auto,
    PlaybackProgressWriter? onHistoryProgress,
    void Function(String message)? onPlaybackError,
  }) async {
    startOffset = offset;
    superResolutionMode = SuperResolutionMode.fromStorageValue(
      GStorage.getSetting(SettingsKeys.defaultSuperResolutionMode),
    );
    hAenable = GStorage.getSetting(SettingsKeys.hAenable);
    androidEnableOpenSLES =
        GStorage.getSetting(SettingsKeys.androidEnableOpenSLES);
    hardwareDecoder = GStorage.getSetting(SettingsKeys.hardwareDecoder);
    autoPlay = GStorage.getSetting(SettingsKeys.autoPlay);
    playerDebugMode = GStorage.getSetting(SettingsKeys.playerDebugMode);

    if (!canInstall()) {
      return null;
    }
    final candidate = _OwnedPlayer(
      Player(
        configuration: PlayerConfiguration(
          bufferSize: cachePolicy.bufferSize,
          osc: false,
          logLevel: MPVLogLevel.values[
              TvMode.enabled && debug.playerLogLevel < 3
                  ? 3
                  : debug.playerLogLevel],
          adBlocker: adBlockerEnabled,
        ),
      ),
      onHistoryProgress,
    );
    final player = candidate.player;
    if (!canInstall()) {
      await candidate.dispose();
      return null;
    }
    _ownedPlayer = candidate;
    candidate.trace.event('created',
        url: videoUrl(),
        detail:
            'owner=${identityHashCode(candidate)} recovery=${recoverySnapshot != null}');
    candidate.subscriptions.add(player.stream.log.listen((event) {
      if (!isCurrentPlayer(player)) return;
      // Keep only warning/error/fatal native context, not verbose HTTP headers.
      if (['warn', 'error', 'fatal'].contains(event.level)) {
        candidate.trace.event('mpv_${event.level}',
            detail: '${event.prefix}: ${event.text}');
      }
    }));
    cachePolicy.startWatching();

    try {
      debug.playerLog.clear();
      await debug.setup(
        player,
        isCurrentPlayer: isCurrentPlayer,
        playerDebugMode: playerDebugMode,
      );
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      var pp = player.platform as NativePlayer;
      // media-kit 默认启用硬盘作为双重缓存，这可以维持大缓存的前提下减轻内存压力
      // media-kit 内部硬盘缓存目录按照 Linux 配置，这导致该功能在其他平台上被损坏
      // 该设置可以在所有平台上正确启用双重缓存
      await pp.setProperty("demuxer-cache-dir", await getPlayerTempPath());
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }
      await cachePolicy.apply();
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }
      await pp.setProperty("af", "scaletempo2=max-speed=8");
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }
      if (Platform.isAndroid) {
        await pp.setProperty("volume-max", "100");
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
        if (androidEnableOpenSLES) {
          await pp.setProperty("ao", "opensles");
        } else {
          await pp.setProperty("ao", "audiotrack");
        }
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
      }

      final bool proxyEnable = GStorage.getSetting(SettingsKeys.proxyEnable);
      if (proxyEnable) {
        final String proxyUrl = GStorage.getSetting(SettingsKeys.proxyUrl);
        final formattedProxy = ProxyUtils.getFormattedProxyUrl(proxyUrl);
        if (formattedProxy != null) {
          await pp.setProperty("http-proxy", formattedProxy);
          if (!isCurrentPlayer(player)) {
            return await _discardIfNotCurrent(candidate);
          }
          KazumiLogger().i('Player: HTTP 代理设置成功 $formattedProxy');
        }
      } else if (SystemProxyService.isActive) {
        final proxy = SystemProxyService.proxyFor('https');
        if (proxy != null) {
          await pp.setProperty("http-proxy", 'http://${proxy.$1}:${proxy.$2}');
          if (!isCurrentPlayer(player)) {
            return await _discardIfNotCurrent(candidate);
          }
          KazumiLogger().i('Player: 跟随系统代理 http://${proxy.$1}:${proxy.$2}');
        }
      }

      await player.setAudioTrack(
        AudioTrack.auto(),
      );
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      String? videoRenderer;
      if (Platform.isAndroid) {
        final String androidVideoRenderer =
            GStorage.getSetting(SettingsKeys.androidVideoRenderer);

        final isEmulator = await PlatformEnvironmentService.isAndroidEmulator();
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
        androidEmulator = isEmulator;

        final androidSdkVersion = androidVideoRenderer == 'auto'
            ? await PlatformEnvironmentService.getAndroidSdkVersion()
            : 0;
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
        final configuration = resolveAndroidVideoConfiguration(
          configuredOutput: androidVideoRenderer,
          isTv: TvMode.enabled,
          androidSdkVersion: androidSdkVersion,
          isEmulator: androidEmulator,
          hardwareAcceleration: hAenable,
          hardwareDecoder: hardwareDecoder,
        );
        videoRenderer = configuration.output;
        hAenable = configuration.hardwareAcceleration;
        hardwareDecoder = configuration.hardwareDecoder;
      }

      if (recoverySnapshot != null) {
        videoRenderer = 'gpu';
        hAenable = false;
        hardwareDecoder = 'no';
        superResolutionMode = SuperResolutionMode.off;
      }
      candidate.trace.event('output',
          detail:
              'vo=$videoRenderer hwdec=$hardwareDecoder hardware=$hAenable');
      var outputTerminalFailure = false;
      if (videoRenderer == 'mediacodec_embed') {
        hAenable = true;
        hardwareDecoder = 'mediacodec';
        superResolutionMode = SuperResolutionMode.off;
        if (TvMode.enabled && onDirectDecoderFailure != null) {
          await pp.setProperty('hwdec-software-fallback', 'no');
          if (!isCurrentPlayer(player))
            return await _discardIfNotCurrent(candidate);
          candidate.subscriptions.add(player.stream.log.listen((event) {
            if (isCurrentPlayer(player) &&
                event.prefix == 'vd' &&
                event.text.trim() ==
                    'Software decoding fallback is disabled.') {
              KazumiLogger().w(
                  'PlaybackDiagnostic session=${identityHashCode(candidate)} output=mediacodec_embed category=hardwareUnavailable signal=mpv_no_software_fallback');
              candidate.trace.finish('hardware_unavailable', error: event.text);
              if (!recoveryBlocksCompletion) {
                recoveryBlocksCompletion = true;
                completed = false;
                onPlaybackError?.call('当前视频没有可用的硬件解码路径，可重试或更换视频源');
              }
            }
            if (isCurrentPlayer(player) &&
                !outputTerminalFailure &&
                isDirectDecoderFailure(
                    prefix: event.prefix, text: event.text)) {
              KazumiLogger().w(
                  'PlaybackDiagnostic session=${identityHashCode(candidate)} output=mediacodec_embed category=hardwareDecoder signal=mpv_hardware_method_failed');
              candidate.trace.finish('hardware_decoder', error: event.text);
              recoveryBlocksCompletion = true;
              completed = false;
              onDirectDecoderFailure(PlaybackRecoverySnapshot(player.state,
                  intendedPlaying: candidate.intendedPlaying));
            }
          }));
        }
      }

      videoController ??= VideoController(
        player,
        configuration: VideoControllerConfiguration(
          vo: videoRenderer,
          enableHardwareAcceleration: hAenable,
          enableAndroidSurfaceProducer: false,
          hwdec: hAenable ? hardwareDecoder : 'no',
          androidAttachSurfaceAfterVideoParameters: false,
        ),
      );
      player.setPlaylistMode(PlaylistMode.none);
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      final outputFailure = CurrentOutputFailureHandler(
        isCurrent: () => isCurrentPlayer(player),
        abort: () {
          outputTerminalFailure = true;
          candidate.hasNativeError = true;
          candidate.abortRecoveryWait();
          recoveryBlocksCompletion = true;
          completed = false;
        },
        report: (failure) {
          candidate.trace.finish('output_${failure.name}');
          final message = switch (failure) {
            CurrentOutputFailure.releasedSession => '当前播放器会话已失效，请重试当前集或更换视频源',
            CurrentOutputFailure.initialization => '视频输出初始化失败，请重试当前集或更换视频源',
            CurrentOutputFailure.firstFrameTimeout => '等待画面超时，可重试当前集或更换视频源',
          };
          KazumiLogger().w(
              'PlaybackDiagnostic session=${identityHashCode(candidate)} output=$videoRenderer category=${failure.name} signal=current_output_failure');
          if (onPlaybackError != null) {
            onPlaybackError(message);
          } else {
            KazumiDialog.showToast(message: message, showActionButton: true);
          }
        },
      );
      bool showPlayerError = GStorage.getSetting(SettingsKeys.showPlayerError);
      candidate.subscriptions.add(player.stream.error.listen((event) {
        PlayerErrorMapper.dispatchCurrentError(event,
            isCurrent: () => isCurrentPlayer(player),
            record: (category) {
              candidate.trace.event('native_error',
                  detail: 'vo=$videoRenderer category=${category.name}');
              candidate.trace.finish('native_error', error: event);
              KazumiLogger().w(
                  'PlaybackDiagnostic session=${identityHashCode(candidate)} output=$videoRenderer category=${category.name} signal=native_error');
            },
            handle: (category) {
              if (category == PlaybackFailureCategory.releasedSession) {
                outputFailure.fail(CurrentOutputFailure.releasedSession);
                return;
              }
              candidate.hasNativeError = true;
              if (isCurrentPlayer(player) && recoverySnapshot != null) {
                candidate.hasNativeError = true;
                candidate.abortRecoveryWait();
                recoveryBlocksCompletion = true;
                completed = false;
              }
              if (isCurrentPlayer(player) &&
                  (recoverySnapshot != null || !recoveryBlocksCompletion)) {
                final actionableMessage = PlayerErrorMapper.toActionableMessage(
                  event,
                  isBuffering: playerBuffering,
                  softwareRecovery: recoverySnapshot != null,
                );
                if (actionableMessage != null) {
                  if (onPlaybackError != null) {
                    onPlaybackError(actionableMessage);
                  } else {
                    KazumiDialog.showToast(
                        message: actionableMessage, showActionButton: true);
                  }
                } else if (showPlayerError) {
                  KazumiDialog.showToast(
                      message: '播放器内部错误 ${event.toString()} ${videoUrl()}',
                      duration: const Duration(seconds: 5),
                      showActionButton: true);
                }
              }
            });
      }));

      if (superResolutionMode != SuperResolutionMode.off) {
        await setShader(superResolutionMode, player: player);
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
      }

      if (videoSourceFormat == VideoSourceFormat.hls) {
        await pp.setProperty('demuxer-lavf-format', 'hls');
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
      }

      final initialOutput = videoController;
      if (TvMode.enabled && recoverySnapshot == null && initialOutput != null) {
        unawaited(observeFirstFrame(
          firstFrame: initialOutput.waitUntilFirstFrameRendered,
          cancelled: candidate.recoveryAborted.future,
        ).then((outcome) {
          if (isCurrentPlayer(player)) {
            candidate.trace.event('first_frame', detail: outcome.name);
          }
          outputFailure.observe(outcome,
              alreadyHandled:
                  candidate.hasNativeError || recoveryBlocksCompletion);
        }));
      }
      candidate.intendedPlaying = recoverySnapshot?.playing ?? autoPlay;
      candidate.trace.event('open', url: videoUrl());
      await player.open(
        Media(videoUrl(),
            start: recoverySnapshot?.position ?? Duration(seconds: offset),
            httpHeaders: httpHeaders),
        play: recoverySnapshot == null && autoPlay,
      );
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      if (cachePolicy.networkAutomatic) {
        KazumiDialog.showToast(message: '移动数据下已自动开启低内存模式，可在播放设置中改为始终关闭');
      }

      return player;
    } catch (error, stackTrace) {
      candidate.trace.finish('initialization_failed', error: error);
      if (identical(_ownedPlayer, candidate)) {
        cachePolicy.stopWatching();
        _ownedPlayer = null;
        videoController = null;
      }
      await candidate.dispose();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> setShader(SuperResolutionMode mode, {Player? player}) async {
    final currentPlayer = player ?? mediaPlayer;
    if (currentPlayer == null) return;
    try {
      var pp = currentPlayer.platform as NativePlayer;
      await pp.waitForPlayerInitialization;
      await pp.waitForVideoControllerInitializationIfAttached;
      if (!identical(mediaPlayer, currentPlayer)) {
        return;
      }
      switch (mode) {
        case SuperResolutionMode.efficiency:
          await pp.command([
            'change-list',
            'glsl-shaders',
            'set',
            buildShadersAbsolutePath(
              shaderAssetService.shadersDirectory.path,
              mpvAnime4KShadersLite,
            ),
          ]);
          break;
        case SuperResolutionMode.quality:
          await pp.command([
            'change-list',
            'glsl-shaders',
            'set',
            buildShadersAbsolutePath(
              shaderAssetService.shadersDirectory.path,
              mpvAnime4KShaders,
            ),
          ]);
          break;
        case SuperResolutionMode.off:
          await pp.command(['change-list', 'glsl-shaders', 'clr', '']);
          break;
      }
      superResolutionMode = mode;
    } catch (e) {
      KazumiLogger().w('PlayerController: failed to set shader', error: e);
    }
  }

  Future<void> setPlaybackSpeed(double playerSpeed) async {
    this.playerSpeed = playerSpeed;
    try {
      mediaPlayer!.setRate(playerSpeed);
    } catch (e) {
      KazumiLogger()
          .e('PlayerController: failed to set playback speed', error: e);
    }
  }

  Future<void> setVolume(double value) async {
    updateVolume(value);
    await syncVolumeToDevice(preciseVolume >= 0 ? preciseVolume : volume);
  }

  @action
  void updateVolume(double value) {
    value = value.clamp(0.0, 100.0);
    preciseVolume = value;
    if (volume.toInt() == value.toInt()) {
      return;
    }
    volume = value;
  }

  /// 外部来源（硬件键、系统面板等）变更音量时同步，并清除手势缓存
  @action
  void applyExternalVolume(double value) {
    value = value.clamp(0.0, 100.0);
    preciseVolume = -1;
    volume = value;
  }

  void invalidatePreciseVolume() {
    preciseVolume = -1;
  }

  Future<void> syncVolumeToDevice([double? value]) async {
    final vol = (value ?? volume).clamp(0.0, 100.0);
    try {
      if (isDesktop()) {
        await mediaPlayer!.setVolume(vol);
      } else {
        await FlutterVolumeController.setVolume(vol / 100);
      }
    } catch (_) {}
  }

  @action
  void syncPlaybackState() {
    final player = mediaPlayer;
    if (player == null) return;

    final PlayerState state;
    try {
      state = player.state;
    } catch (_) {
      return;
    }
    if (TvInputLifecycle.active)
      TvInputLifecycle.trace('player_state', {
        'source': 'existing_timer_cached_state',
        'playerIdentity': identityHashCode(player),
        'rate': state.rate,
        'requestedRate': playerSpeed,
        'playing': state.playing,
        'positionMs': state.position.inMilliseconds,
        'durationMs': state.duration.inMilliseconds,
      });
    if (playing != state.playing) {
      playing = state.playing;
    }
    if (isBuffering != state.buffering) {
      isBuffering = state.buffering;
    }
    if (currentPosition != state.position) {
      currentPosition = state.position;
    }
    if (buffer != state.buffer) {
      buffer = state.buffer;
    }
    if (duration != state.duration) {
      duration = state.duration;
    }
    final ended = state.completed && !recoveryBlocksCompletion;
    if (completed != ended) {
      completed = ended;
    }
  }

  Future<void> playOrPause({
    required Future<void> Function() pause,
    required Future<void> Function() play,
  }) async {
    if (playerPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<bool> waitForRecoveredFrame(Player player) {
    final owner = _ownedPlayer;
    final output = videoController;
    if (owner == null || owner.player != player || output == null) {
      return Future.value(false);
    }
    return waitForRecoveryFrame(
      firstFrame: output.waitUntilFirstFrameRendered,
      aborted: owner.recoveryAborted.future,
      isCurrent: () => isCurrentPlayer(player) && !owner.hasNativeError,
    );
  }

  Future<void> stop() async {
    cachePolicy.stopWatching();
    final ownedPlayer = _ownedPlayer;
    _ownedPlayer = null;
    videoController = null;
    playing = false;
    loading = true;
    // media_kit stops playback as part of disposal before releasing native
    // resources. Debug subscriptions can be cancelled concurrently.
    final previousDisposal = _pendingDisposal;
    final disposal = Future.wait([
      previousDisposal,
      ownedPlayer?.dispose() ?? Future<void>.value(),
      _cancelDebugInfo(),
    ]).then((_) {
      if (ownedPlayer != null) _lastReleaseSucceeded = ownedPlayer.released;
    });
    _pendingDisposal = disposal;
    await disposal;
  }

  Future<Uint8List?> screenshot({String format = 'image/jpeg'}) async {
    return await mediaPlayer!.screenshot(format: format);
  }

  Future<Uint8List?> screenshotPng() async {
    final player = mediaPlayer;
    if (player == null) {
      return null;
    }
    return await screenshotService.capturePng(player);
  }
}
