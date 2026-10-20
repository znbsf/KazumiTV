// QA entry only. Never imported by production main.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
// ignore: depend_on_referenced_packages
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mobx/mobx.dart' show reaction;
import 'package:logger/logger.dart' as qa_log;
import 'package:kazumi/pages/player/controller/player_playback_controller.dart';
import 'package:kazumi/pages/player/controller/player_debug_controller.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/video_source/resolved_source_cache.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/platform/webview_feature_service.dart';
import 'package:kazumi/services/source_health/source_health.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/video_source/services.dart';
import 'package:kazumi/webview/video/impl/video_webview_android_impl.dart';
import 'package:kazumi/webview/video/video_webview_controller.dart';
import 'package:kazumi/utils/http_headers.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart' show RuleChapterTrace;
import 'gecko_controller.dart';
import 'rule_snapshot.dart';
import 'failure_snapshot.dart';
import 'app_fallback_service.dart';
import 'media_root_observer.dart';
import 'playback_observation.dart';
import 'case_selection.dart';
import 'lifecycle_gate.dart';
import 'lifecycle_host.dart';
import 'selection_snapshot.dart';
import 'chapter_diagnostic_runtime.dart';
import 'launch_probe.dart';

final _shaderAssets = ShaderAssetService();

Future<void> main() async {
  if (qaLaunchOnlyBuild) {
    HttpOverrides.global = QaNoNetworkOverrides();
    qa_log.Logger.level = qa_log.Level.off;
  }
  WidgetsFlutterBinding.ensureInitialized();
  final probe = qaLaunchOnlyBuild ? const QaLaunchProbe() : null;
  try {
    if (probe != null) await probe.mark('dart_binding');
    if (!kDebugMode || (await qaBootstrapStep(probe, 'identity', PackageInfo.fromPlatform)).packageName !=
        'com.znbsf.kazumi.fluttertv.parserqa') {
      throw StateError('Isolated parserQa debug identity required');
    }
    final config = jsonDecode((await qaBootstrapStep(probe, 'config',
        () => qaChannel.invokeMethod<String>('config')))!)
        as Map<String, dynamic>;
    if (!qaLaunchConfigAllowed(config, offlineBuild: qaLaunchOnlyBuild)) {
      throw StateError('qa_launch_only_input_rejected');
    }
    // QA process only: production HTTP loggers can print full request addresses.
    if (config['selection_only'] == true) qa_log.Logger.level = qa_log.Level.off;
    await qaBootstrapStep(probe, 'tvmode', TvMode.initialize);
    // QA debug identity was checked above. Simulate the TV build flag while
    // retaining the real SDK/provider/ABI detection and native MainActivity.
    // ignore: invalid_use_of_visible_for_testing_member
    TvMode.setEnabledForTesting(true);
    if (config['engine'] != 'gecko') await qaBootstrapStep(probe, 'webview', WebViewFeatureService.initialize);
    await qaBootstrapStep(probe, 'mediakit', MediaKit.ensureInitialized);
    final root = await qaBootstrapStep(probe, 'path', getApplicationSupportDirectory);
    await qaBootstrapStep(probe, 'hive', () => Hive.initFlutter('${root.path}/hive'));
    await qaBootstrapStep(probe, 'storage', GStorage.init);
    if (config['engine'] == 'app') await qaBootstrapStep(probe, 'shaders', _shaderAssets.copyShadersToExternalDirectory);
    if (probe != null) {
      await probe.step('dio_guard', () {
        for (final dio in [DioFactory.apiDio, DioFactory.rulesRepoDio,
            DioFactory.pluginDio, DioFactory.downloadDio]) {
          dio.interceptors.insert(0, QaDioNetworkDeny());
        }
      });
      await probe.mark('dart_runapp');
      runApp(MaterialApp(home: QaLaunchOnlyPage(probe: probe)));
      return;
    }
    runApp(MaterialApp(home: QaLifecycleHost(config: config, channel: qaChannel,
      pageBuilder: (c, ticket, finished, signal, disposed) => BatchCase(c,
        key: ValueKey(ticket.generation), ticket: ticket, onFinished: finished,
        onSignal: signal, onPageDisposed: disposed))));
  } catch (error) {
    await probe?.failure(error);
    rethrow;
  }
}

class BatchCase extends StatefulWidget {
  const BatchCase(this.config, {required this.ticket, required this.onFinished,
    required this.onSignal, required this.onPageDisposed, super.key});
  final Map<String, dynamic> config;
  final QaCaseTicket ticket;
  final void Function(Map<String, dynamic>) onFinished;
  final void Function(Map<String, Object?>) onSignal;
  final VoidCallback onPageDisposed;
  @override
  State<BatchCase> createState() => _BatchCaseState();
}

class _BatchCaseState extends State<BatchCase> {
  VideoController? _video;
  String _stage = 'starting';
  bool get _current => mounted && !widget.ticket.cancelled;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final c = widget.config;
    final appProfile = c['engine'] == 'app';
    final watch = Stopwatch()..start();
    final run = HealthRun();
    IVideoSourceService? resolver;
    widget.ticket.attachCancel(() { run.cancel(); resolver?.cancel(); });
    final result = <String, dynamic>{
      'id': c['id'], 'engine': c['engine'], 'stage': 'starting',
      'environment': await qaChannel.invokeMethod('environment'),
      'timings_ms': <String, int>{},
      'player': appProfile ? 'production PlayerPlaybackController/TV defaults' : 'media_kit/emulator/gpu/software/muted',
      'parser_profile': appProfile ? 'production factory/default UA/legacy capability detection' : 'shared-script/document-start/all-frames/fixed-UA',
      'coverage': appProfile ? 'service path; no TV UI navigation/history/danmaku' : 'controlled engine comparison',
      'diagnostics': <String>[],
    };
    if (c['selection_only'] == true) {
      result.addAll({'selection_only': true, 'parser': 'not_run', 'media': 'not_run',
        'player': 'not_run (selection-only)', 'source_request_logging': 'suppressed'});
    }
    final timings = result['timings_ms'] as Map<String, int>;
    Player? player;
    PlayerPlaybackController? appPlayback;
    StreamSubscription<String>? errors;
    String phase = 'search';
    try {
      if (!_current) throw const VideoSourceCancelledException();
      final selectionTail = qaSelectionTailEnabled(c);
      if (selectionTail) result['selection_tail1'] = true;
      if (c['selection_only'] == true && (!appProfile || c['rule'] == null)) {
        throw const FormatException('Selection-only requires App profile and fixed rule');
      }
      if (c['chapter_selector_diagnostic'] == true && c['selection_only'] != true) {
        throw const FormatException('Chapter diagnostic is selection-only');
      }
      final observationWindow = qaPlaybackObservationWindow(c['observe_playback_seconds']);
      final ua = c['user_agent'] as String;
      String episodeUrl;
      Map<String, String> headers = {'user-agent': appProfile ? getRandomUA() : ua};
      bool legacy = false;
      bool adBlocker = false;
      if (c['rule'] != null) {
        final snapshot = BatchRuleSnapshot.fromJson(
            Map<String, dynamic>.from(c['rule']),
            variant: c['rule_variant'] as String? ?? 'effective');
        final plugin = snapshot.plugin;
        result['observed_rule_snapshot'] = snapshot.identity;
        result['rule_fingerprint'] = ruleFingerprint(plugin);
        if (c['chapter_selector_diagnostic'] == true && !aafunDiagnosticBinding(c, snapshot.identity)) {
          result['chapter_selector_diagnostic'] = {'status': 'not_run', 'reason': 'rule_or_case_identity'};
          result['stage'] = 'chapter_diagnostic_not_run';
          return;
        }
        final hits = await run.wait(plugin.queryBangumi(c['keyword'] as String,
            shouldRethrow: true, cancelToken: run.token), const Duration(seconds: 10));
        timings['search'] = watch.elapsedMilliseconds;
        if (hits.data.isEmpty) { result['stage'] = 'no_match'; return; }
        final match = matchHealthTitle(hits.data, List<String>.from(c['names']));
        if (match == null) {
          result['stage'] = 'no_unique_match';
          return;
        }
        phase = 'chapters';
        final beginChapters = watch.elapsedMilliseconds;
        if (c['chapter_selector_diagnostic'] == true) {
          result['matched_title'] = match.name;
          final detailHash = sha256.convert(utf8.encode(plugin.buildFullUrl(match.src))).toString();
          result['matched_detail_page_sha256'] = detailHash;
          result['chapter_selector_diagnostic'] = <String, Object?>{
            'status': 'not_run', 'reason': 'normal_query_failed_or_incomplete', 'worker_cleanup': 'not_created'};
          if (match.name != '葬送的芙莉莲' || detailHash != aafunDetailSha) {
            result['chapter_selector_diagnostic'] = {'status': 'not_run', 'reason': 'work_or_detail_identity'};
            result['stage'] = 'chapter_diagnostic_not_run';
            return;
          }
          final tap = QaChapterResponseTap(DioFactory.pluginDio, aafunDetailSha);
          late final RuleChapterTrace trace;
          late final bool removed;
          try {
            trace = await run.wait(plugin.traceChapters(match.src, cancelToken: run.token),
                const Duration(seconds: 10));
          } finally {
            removed = tap.close();
            (result['chapter_selector_diagnostic'] as Map<String, Object?>).addAll({
              'response_metadata': Map<String, Object?>.from(tap.metadata),
              'interceptor_removed': removed});
            if (!removed) result['diagnostic_cleanup'] = 'unconfirmed';
            if (tap.metadata['challenge'] == true) result['diagnostic_challenge_observed'] = true;
          }
          timings['chapters'] = watch.elapsedMilliseconds - beginChapters;
          final reason = tap.rejection(trace.rawResponse);
          Map<String, Object?> compared;
          if (!_current || run.cancelled) {
            compared = {'status': 'not_run', 'reason': 'cancelled', 'worker_cleanup': 'not_created'};
          } else if (reason != null || c['chapter_diagnostic_semantic_rule'] is! Map || !removed) {
            compared = {'status': 'not_run', 'reason': reason ?? 'semantic_input_or_interceptor', 'worker_cleanup': 'not_created'};
          } else {
            phase = 'chapter_diagnostic';
            compared = await boundedQaWorker(worker: chapterSelectorWorker,
              input: {'raw': trace.rawResponse, 'base': plugin.toJson(includeLocalMetadata: false),
                'semantic': Map<String, dynamic>.from(c['chapter_diagnostic_semantic_rule'] as Map)},
              remainingBudget: const Duration(seconds: 60) - watch.elapsed,
              isCancelled: () => !_current || run.cancelled);
          }
          compared.addAll({'response_metadata': Map<String, Object?>.from(tap.metadata), 'interceptor_removed': removed});
          result['chapter_selector_diagnostic'] = compared;
          if (compared['worker_cleanup'] == 'unconfirmed') result['diagnostic_cleanup'] = 'unconfirmed';
          result['stage'] = compared['status'] == 'observed' ? 'chapter_diagnostic' : 'chapter_diagnostic_not_run';
          return;
        }
        final roads = await run.wait(plugin.queryChapterRoads(match.src,
            cancelToken: run.token), const Duration(seconds: 10));
        timings['chapters'] = watch.elapsedMilliseconds - beginChapters;
        final candidate = HealthCandidate(plugin, match, roads.where((r) =>
            r.data.isNotEmpty && r.identifier.length == r.data.length).toList());
        if (c['selection_only'] == true) {
          result['matched_title'] = match.name;
          result['matched_detail_page_sha256'] = sha256.convert(utf8.encode(plugin.buildFullUrl(match.src))).toString();
          result['selection_snapshot'] = {
            ...qaSelectionSnapshot(candidate.roads, plugin.buildFullUrl, tail1: selectionTail),
            'raw_road_count': roads.length,
            'road_index_basis': 'filtered production playback candidates',
          };
          result['stage'] = 'selection_only';
          return;
        }
        final road = (c['road'] as int? ?? 0);
        final episode = (c['episode'] as int? ?? 0);
        if (road < 0 || road >= candidate.roads.length || episode < 0 ||
            episode >= candidate.roads[road].data.length) {
          result['stage'] = 'episode_missing';
          return;
        }
        episodeUrl = plugin.buildFullUrl(candidate.roads[road].data[episode]);
        result['matched_title'] = match.name;
        result['road_name'] = candidate.roads[road].name;
        result['episode_label'] = candidate.roads[road].identifier[episode];
        result['episode_page_sha256'] = sha256.convert(utf8.encode(episodeUrl)).toString();
        if (!qaEpisodeMatches(c, url: episodeUrl,
            label: candidate.roads[road].identifier[episode])) {
          result['stage'] = 'sample_identity_mismatch';
          return;
        }
        headers = appProfile ? plugin.buildHttpHeaders() : {...plugin.buildHttpHeaders(), 'user-agent': ua};
        legacy = plugin.useLegacyParser;
        adBlocker = plugin.adBlocker || GStorage.getSetting(SettingsKeys.forceAdBlocker);
      } else {
        episodeUrl = c['url'] as String;
      }
      timings['search_chapters'] = watch.elapsedMilliseconds;
      result['episode_page_sha256'] = sha256.convert(utf8.encode(episodeUrl)).toString();
      phase = 'resolve';
      if (_current) setState(() => _stage = phase);
      final beginResolve = watch.elapsedMilliseconds;
      resolver = WebViewVideoSourceService(diagnosticSink: (record) {
        final diagnostics = result['diagnostics'] as List<String>;
        if (diagnostics.length < 80) diagnostics.add(record);
      }, controllerFactory: () {
        if (appProfile) {
          final controller = VideoWebviewControllerFactory.getController();
          result['actual_controller'] = controller.runtimeType.toString();
          result['document_start_supported'] = WebViewFeatureService.isDocumentStartScriptSupported;
          result['legacy_player_compat_eligible'] = WebViewFeatureService.needsLegacyPlayerCompat;
          return controller;
        }
        if (c['engine'] == 'gecko') return GeckoQaController(ua);
        return VideoWebviewAndroidImpl(userAgent: ua);
      });
      if (appProfile && c['app_gecko_fallback'] == true) {
        final primary = resolver;
        final eligible = WebViewFeatureService.needsLegacyPlayerCompat &&
            !WebViewFeatureService.isDocumentStartScriptSupported && !legacy;
        final events = <Map<String, Object?>>[];
        result['fallback_events'] = events;
        result['fallback_policy'] = {
          'explicit_qa_opt_in': true, 'eligible': eligible,
          'total_resolution_budget_ms': 25000, 'max_fallbacks': 1,
          'media_headers': 'unchanged production Plugin.buildHttpHeaders',
          'gecko_ua': 'same UA as media headers; primary keeps App default UA',
        };
        resolver = QaAppFallbackService(
          primaryFactory: () => primary,
          fallbackFactory: () {
            result['fallback_controller'] = 'GeckoQaController';
            return WebViewVideoSourceService(
            nestedPageTimeout: Duration.zero,
            controllerFactory: () => GeckoQaController(headers['user-agent'] ?? ua),
            diagnosticSink: (record) {
              final diagnostics = result['diagnostics'] as List<String>;
              if (diagnostics.length < 80) diagnostics.add(record);
            });
          },
          enabled: true, eligible: eligible,
          onEvent: (event) {
            if (events.length < 32) events.add(event);
            widget.onSignal(event);
          },
        );
      }
      final cache = ResolvedSourceCache.shared;
      final cacheKey = jsonEncode([c['id'], c['rule'], c['road'] ?? 0, c['episode'] ?? 0, episodeUrl]);
      Future<VideoSource> fresh() => resolver!.resolve(episodeUrl, useLegacyParser: legacy,
          timeout: const Duration(seconds: 15));
      final attempt = appProfile ? await cache.resolve(key: cacheKey, offset: 0,
          headers: headers, fresh: fresh, isCurrent: () => _current && !run.cancelled)
          : ResolvedSourceAttempt(await fresh(), headers, fromCache: false);
      final source = attempt.source;
      if (!_current) throw const VideoSourceCancelledException();
      result['from_confirmed_cache'] = attempt.fromCache;
      timings['resolve'] = watch.elapsedMilliseconds - beginResolve;
      result['stage'] = 'resolved';
      // Never persist signed media URLs or query strings in exported reports.
      result['media_host'] = Uri.tryParse(source.url)?.host;
      result['media_sha256'] = sha256.convert(utf8.encode(source.url)).toString();
      if (c['observe_media_root'] == true) {
        final available = const Duration(seconds: 35) - watch.elapsed;
        result['media_root_observation'] = await observeMediaRoot(
          enabled: true,
          debug: kDebugMode,
          packageName: (await PackageInfo.fromPlatform()).packageName,
          mediaUrl: source.url,
          headers: attempt.headers,
          isCancelled: () => run.cancelled || !_current,
          budget: available,
        );
      }
      phase = 'first_frame';
      if (_current) setState(() => _stage = phase);
      final beginPlay = watch.elapsedMilliseconds;
      if (appProfile) {
        appPlayback = PlayerPlaybackController(shaderAssetService: _shaderAssets,
            debug: PlayerDebugController(), videoUrl: () => source.url,
            isLocalPlayback: () => false);
        final playback = appPlayback;
        final rendered = Completer<void>();
        var playerErrorCount = 0;
        final disposeReaction = reaction<VideoController?>(
          (_) => playback.videoController, (video) {
            if (video == null || !_current) return;
            setState(() => _video = video);
            video.waitUntilFirstFrameRendered.then((_) {
              if (!rendered.isCompleted) rendered.complete();
            }, onError: (Object e, StackTrace s) {
              if (!rendered.isCompleted) rendered.completeError(e, s);
            });
          });
        try {
          final frame = rendered.future.timeout(const Duration(seconds: 20));
          final opened = playback.createVideoController(attempt.headers, adBlocker,
            videoSourceFormat: source.format, canInstall: () => _current && !run.cancelled,
            onPlaybackError: (_) {
              if (observationWindow != null) playerErrorCount++;
              if (!rendered.isCompleted) rendered.completeError(StateError('production_player_error'));
            }).then((created) {
              if (created == null) throw StateError('production_player_retired');
              timings['media_open'] = watch.elapsedMilliseconds - beginPlay;
              player = created;
              return created.setVolume(0);
            }).timeout(const Duration(seconds: 15));
          await Future.wait([frame, opened]);
          timings['first_frame'] = watch.elapsedMilliseconds - beginPlay;
          result['stage'] = 'first_frame';
          await cache.rememberAfterFirstFrame(key: cacheKey, attempt: attempt,
              firstFrame: rendered.future, isCurrent: () => _current && !run.cancelled);
          result['player_settings'] = {'tv': TvMode.enabled,
            'emulator': playback.androidEmulator, 'hwdec': playback.hardwareDecoder,
            'hardware_acceleration': playback.hAenable,
            'renderer_setting': GStorage.getSetting(SettingsKeys.androidVideoRenderer),
            'ad_blocker': adBlocker};
          final start = player!.state.position;
          if (observationWindow == null) {
            await Future<void>.delayed(const Duration(seconds: 2));
          } else {
            result['playback_observation'] = await observeQaPlayback(
              window: observationWindow,
              remainingBudget: const Duration(seconds: 60) - watch.elapsed,
              isCancelled: () => run.cancelled || !_current,
              read: () => QaPlaybackState(
                positionMs: player!.state.position.inMilliseconds,
                playing: player!.state.playing, buffering: player!.state.buffering,
                completed: player!.state.completed,
                bufferMs: player!.state.buffer.inMilliseconds,
                durationMs: player!.state.duration.inMilliseconds,
                errorCount: playerErrorCount),
            );
          }
          result['progress_ms'] = (player!.state.position - start).inMilliseconds;
        } finally { disposeReaction(); }
        return;
      }
      final playbackError = Completer<void>();
      player = Player(configuration: const PlayerConfiguration(
          bufferSize: 8 * 1024 * 1024, osc: false));
      errors = player.stream.error.listen((message) {
        if (healthPlayerError(message) != null && !playbackError.isCompleted) {
          result['player_error'] = healthPlayerError(message);
          playbackError.completeError(StateError('player_error'));
        }
      });
      // Fixed emulator path, shared by both engines; never affects formal settings.
      final video = VideoController(player, configuration: const VideoControllerConfiguration(
        vo: 'gpu', hwdec: 'no', enableHardwareAcceleration: false,
        enableAndroidSurfaceProducer: false, androidAttachSurfaceAfterVideoParameters: false,
      ));
      if (_current) setState(() => _video = video);
      await WidgetsBinding.instance.endOfFrame;
      if (!_current) throw const VideoSourceCancelledException();
      await player.setVolume(0);
      // Subscribe before opening so early errors are handled.
      final frame = Future.any<void>([
        video.waitUntilFirstFrameRendered, playbackError.future,
      ]).timeout(const Duration(seconds: 15));
      final opened = player.open(Media(source.url, httpHeaders: headers)).then((_) {
        timings['media_open'] = watch.elapsedMilliseconds - beginPlay;
      });
      await Future.wait([frame, opened.timeout(const Duration(seconds: 8))]);
      timings['first_frame'] = watch.elapsedMilliseconds - beginPlay;
      result['stage'] = 'first_frame';
      final start = player.state.position;
      await Future<void>.delayed(const Duration(seconds: 2));
      result['progress_ms'] = (player.state.position - start).inMilliseconds;
    } on VideoSourceCancelledException {
      result['stage'] = 'cancelled';
    } on VideoSourceTimeoutException {
      result['stage'] = 'resolve_timeout';
    } on TimeoutException {
      result['stage'] = '${phase}_timeout';
    } on NoResultException {
      result['stage'] = 'no_match';
    } on CaptchaRequiredException {
      result['stage'] = 'captcha';
    } catch (error) {
      result['stage'] = '${phase}_error';
      result['error_type'] = error.runtimeType.toString();
      final failure = batchFailureSnapshot(error);
      result['failure_snapshot'] = failure;
      if (failure['actual_challenge_observed'] == true) {
        result['observed_stage'] = result['stage'];
        result['stage'] = 'captcha';
      }
    } finally {
      timings['total_before_cleanup'] = watch.elapsedMilliseconds;
      run.cancel();
      resolver?.cancel();
      if (mounted) setState(() => _video = null);
      final retiringPlayback = appPlayback;
      final retiringPlayer = player;
      final retiringResolver = resolver;
      final retiringErrors = errors;
      result.addAll(await retireQaResources(
        subscription: retiringErrors == null ? null : () => retiringErrors.cancel(),
        player: retiringPlayback != null ? () async {
          await retiringPlayback.stop();
          if (!retiringPlayback.lastReleaseSucceeded) throw StateError('production_player_release_failed');
        } : retiringPlayer == null ? null : () => retiringPlayer.dispose(),
        resolver: retiringResolver == null ? null : () => retiringResolver.dispose(),
      ));
      if (result['diagnostic_cleanup'] == 'unconfirmed') result['cleanup'] = 'unconfirmed';
      if (result['diagnostic_challenge_observed'] == true && result['stage'] != 'captcha') {
        result['observed_stage'] = result['stage'];
        result['stage'] = 'captcha';
      }
      timings['total'] = watch.elapsedMilliseconds;
      widget.onFinished(result);
      if (_current) setState(() => _stage = result['stage'] as String);
    }
  }

  @override
  void dispose() {
    widget.ticket.cancel();
    widget.onPageDisposed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.black,
    body: Stack(children: [
      if (_video != null) Positioned.fill(child: Video(controller: _video!, controls: NoVideoControls)),
      Align(alignment: Alignment.topLeft, child: Text('Parser QA: $_stage', style: const TextStyle(color: Colors.white))),
    ]));
}
