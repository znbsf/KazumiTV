import 'package:kazumi/services/source_health/source_health_preferences.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/tv_visuals.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/platform/platform_environment_service.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/player/android_video_output.dart';
import 'package:kazumi/services/source_health/source_health.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/video_source/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Only opened from the detail route; no player route is active underneath it.
/// Owns one visible test player, never writes watch history or favorites.
class SourceHealthPage extends StatefulWidget {
  const SourceHealthPage({
    super.key,
    required this.subject,
    required this.plugins,
    this.autoSelect = false,
    this.playbackProbe,
    this.persistRecord,
  });
  final BangumiItem subject;
  final List<Plugin> plugins;
  final bool autoSelect;
  final HealthPlaybackProbe? playbackProbe;
  final Future<void> Function(HealthRecord)? persistRecord;
  @override
  State<SourceHealthPage> createState() => _SourceHealthPageState();
}

class _SourceHealthPageState extends State<SourceHealthPage> {
  HealthPlaybackLease? _lease;
  final _run = HealthRun();
  final _results = <HealthRecord>[];
  VideoController? _video;
  String _message = '准备检测';
  String _environment = '';
  bool _running = false;
  bool _closing = false;
  bool _releaseConfirmed = true;
  HealthRun? _active;
  HealthCandidate? _selected;
  List<HealthRecord> _stored = [];
  bool _autoEnabled = true;
  @override
  void initState() {
    super.initState();
    _environment =
        '${ApiEndpoints.version}|${Platform.operatingSystem}|${Platform.operatingSystemVersion}|'
        '${GStorage.getSetting(SettingsKeys.androidVideoRenderer)}|${GStorage.getSetting(SettingsKeys.hardwareDecoder)}|${GStorage.getSetting(SettingsKeys.hAenable)}';
    _stored = HealthRecordCodec.decode(
      GStorage.getSetting(SettingsKeys.sourceHealthRecords),
    );
    _autoEnabled = GStorage.getSetting(SettingsKeys.firstSourceAutoSelect);
    if (widget.autoSelect) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  @override
  void dispose() {
    _run.cancel();
    _active?.cancel();
    super.dispose();
  }

  Future<void> _save(HealthRecord record) async {
    _stored.removeWhere(
      (r) => r.subject == record.subject && r.rule == record.rule,
    );
    _stored.add(record);
    await GStorage.putSetting(
      SettingsKeys.sourceHealthRecords,
      HealthRecordCodec.encode(_stored),
    );
  }

  Future<HealthStage> _play(HealthCandidate candidate, HealthRun child) async {
    _active = child;
    _releaseConfirmed = false;
    final resolver = WebViewVideoSourceService();
    Player? player;
    StreamSubscription<String>? errors;
    final playbackError = Completer<String>();
    Future<void>? cleanup;
    Future<void> release() => cleanup ??= () async {
          resolver.cancel();
          if (mounted) setState(() => _video = null);
          // Disposing the player is mandatory before another candidate acquires it.
          await errors?.cancel();
          await player?.dispose();
          await resolver.dispose();
          _releaseConfirmed = true;
          if (!_running) _lease?.release();
          if (mounted) setState(() {});
        }();
    child.cleanup = release;
    try {
      if (mounted) setState(() => _message = '解析：${candidate.plugin.name}');
      final source = await resolver.resolve(
        candidate.plugin.buildFullUrl(candidate.roads.first.data.first),
        useLegacyParser: candidate.plugin.useLegacyParser,
        timeout: const Duration(seconds: 12),
      );
      if (child.cancelled || !mounted) throw const HealthCancelled();
      final androidConfiguration = Platform.isAndroid
          ? resolveAndroidVideoConfiguration(
              configuredOutput: GStorage.getSetting(
                SettingsKeys.androidVideoRenderer,
              ),
              isTv: TvMode.enabled,
              hardwareAcceleration: GStorage.getSetting(SettingsKeys.hAenable),
              hardwareDecoder: GStorage.getSetting(SettingsKeys.hardwareDecoder),
              androidSdkVersion:
                  await PlatformEnvironmentService.getAndroidSdkVersion(),
              isEmulator: await PlatformEnvironmentService.isAndroidEmulator(),
            )
          : null;
      if (child.cancelled || !mounted) throw const HealthCancelled();
      player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 8 * 1024 * 1024,
          osc: false,
        ),
      );
      errors = player.stream.error.listen((message) {
        final reason = healthPlayerError(message);
        if (reason != null && !playbackError.isCompleted) {
          playbackError.complete(reason);
        }
      });
      final controller = VideoController(
        player,
        configuration: VideoControllerConfiguration(
          vo: androidConfiguration?.output,
          enableAndroidSurfaceProducer: false,
          enableHardwareAcceleration: androidConfiguration?.hardwareAcceleration ??
              GStorage.getSetting(SettingsKeys.hAenable),
          hwdec: androidConfiguration?.effectiveHardwareDecoder ??
              (GStorage.getSetting(SettingsKeys.hAenable)
                  ? GStorage.getSetting(SettingsKeys.hardwareDecoder)
                  : 'no'),
          androidAttachSurfaceAfterVideoParameters: false,
        ),
      );
      setState(() {
        _video = controller;
        _message = '验证首帧：${candidate.plugin.name}（静音）';
      });
      await child.wait(
        WidgetsBinding.instance.endOfFrame,
        const Duration(seconds: 3),
      );
      if (child.cancelled || !mounted) throw const HealthCancelled();
      await player.setVolume(0);
      if (child.cancelled) throw const HealthCancelled();
      await child.wait(
        player.open(
          Media(source.url, httpHeaders: candidate.plugin.buildHttpHeaders()),
        ),
        const Duration(seconds: 8),
      );
      try {
        await child.wait(
          Future.any<void>([
            controller.waitUntilFirstFrameRendered,
            playbackError.future.then<void>(
              (reason) => throw HealthPlaybackFailure(reason),
            ),
          ]),
          const Duration(seconds: 10),
        );
      } on TimeoutException {
        return HealthStage.resolved;
      }
      if (child.cancelled) throw const HealthCancelled();
      return HealthStage.firstFrame;
    } finally {
      await release();
      _active = null;
    }
  }

  Future<void> _start() async {
    if (_running || _run.cancelled) return;
    _lease = HealthPlaybackLease.acquire();
    if (_lease == null) {
      setState(() => _message = '已有播放器正在释放，请稍后重试');
      return;
    }
    setState(() {
      _running = true;
      _selected = null;
      _results.clear();
      _message = '开始检测';
    });
    try {
      _environment =
          '${ApiEndpoints.version}|${Platform.operatingSystem}|${Platform.operatingSystemVersion}|'
          '${GStorage.getSetting(SettingsKeys.androidVideoRenderer)}|${GStorage.getSetting(SettingsKeys.hardwareDecoder)}|${GStorage.getSetting(SettingsKeys.hAenable)}';
      final item = widget.subject;
      final preferred = SourceHealthPreferences.preferred(
        item.id,
        widget.plugins,
      );
      final plugins = widget.autoSelect && preferred != null
          ? [preferred]
          : SourceHealthService.rank(
              widget.plugins,
              _stored,
              item.id,
              _environment,
              DateTime.now(),
            );
      final writes = <Future<void>>[];
      await SourceHealthService(
        maxRules: widget.autoSelect ? 3 : 12,
        total: Duration(seconds: widget.autoSelect ? 75 : 180),
      ).probe(
        subject: item.id,
        keyword: item.nameCn.isEmpty ? item.name : item.nameCn,
        names: [item.name, item.nameCn, ...item.alias],
        plugins: plugins,
        environment: _environment,
        run: _run,
        playback: (candidate, child) async {
          final result =
              await (widget.playbackProbe ?? _play)(candidate, child);
          if (result == HealthStage.firstFrame && !child.cancelled) {
            _selected = candidate;
          }
          return result;
        },
        stopOnFirstFrame: widget.autoSelect,
        onResult: (r, done, count) {
          writes.add(widget.persistRecord?.call(r) ?? _save(r));
          if (mounted) {
            setState(() {
              _results.add(r);
              _message = '已检测 $done / $count';
            });
          }
        },
      );
      await Future.wait(writes);
      if (!mounted) return;
      setState(() => _message = _run.cancelled ? '检测已停止' : '检测结束；结果仅适用于本部番剧');
      if (!_releaseConfirmed) setState(() => _message = '播放器释放尚未确认，已停止检测，请返回');
      if (widget.autoSelect &&
          !_run.cancelled &&
          _releaseConfirmed &&
          _selected != null) {
        setState(() => _running = false);
        _lease?.release();
        await WidgetsBinding.instance.endOfFrame;
        if (mounted && !_run.cancelled) Navigator.pop(context, _selected);
        return;
      }
    } catch (_) {
      if (mounted) setState(() => _message = '检测失败，请手动选择播放源');
    } finally {
      _running = false;
      if (_releaseConfirmed) _lease?.release();
      if (mounted) setState(() {});
    }
  }

  Future<void> _exit() async {
    if (_closing) return;
    _closing = true;
    _run.cancel();
    final active = _active;
    if (active != null && !await active.close()) {
      _closing = false;
      if (mounted) setState(() => _message = '播放器仍在释放，暂不能进入播放；请稍后再返回');
      return;
    }
    if (!_releaseConfirmed) {
      _closing = false;
      return;
    }
    if (!mounted) return;
    setState(() => _running = false);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  String _freshness(HealthRecord record) {
    for (final plugin in widget.plugins) {
      if (plugin.name == record.rule &&
          record.current(
              ruleFingerprint(plugin), _environment, DateTime.now())) {
        return '有效';
      }
    }
    return '已失效，请重新检测';
  }

  String _reason(String code) => switch (code) {
        'decoder_or_output_error' => '解码或画面输出失败',
        'media_request_error' => '媒体请求失败',
        'media_format_error' => '媒体格式不支持',
        'no_unique_title_match' => '需要手动确认同一作品',
        'chapters_failed' => '剧集列表读取失败',
        'manual_verification_required' => '请手动验证后重试',
        'time_budget_exhausted' => '已达到时间上限',
        'frame_observed' => '已确认首帧',
        'frame_not_observed' => '未确认首帧',
        _ => '仅供本次检测参考',
      };

  String _label(HealthStage stage) => switch (stage) {
        HealthStage.noMatch => '搜索无结果',
        HealthStage.searchHit => '搜索命中；未确认匹配/剧集',
        HealthStage.chapters => '剧集可读取；媒体未验证',
        HealthStage.resolved => '媒体可解析；未观察到首帧',
        HealthStage.firstFrame => '已观察到播放器首帧',
        HealthStage.captcha => '需要手动验证码',
        HealthStage.timeout => '检测超时',
        HealthStage.error => '请求或播放失败',
      };
  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_running && _releaseConfirmed,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _exit();
        },
        child: Scaffold(
          appBar: AppBar(title: Text(widget.autoSelect ? '首次自动选源' : '源健康检测')),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                widget.subject.nameCn.isEmpty
                    ? widget.subject.name
                    : widget.subject.nameCn,
                style: TvVisuals.control,
              ),
              const Text('检测首帧不代表后续完整播放成功，正式播放仍可能因网络变化失败，可手动换源。'),
              const Text(
                '串行检测已加载规则，最多 12 个 / 3 分钟。首次选源最多 3 个 / 75 秒。结果 24 小时有效，规则或播放环境变化后失效。单部成功不代表全站可用。',
              ),
              if (!widget.autoSelect)
                SwitchListTile(
                  title: const Text('首次播放自动选源'),
                  subtitle: const Text('仅无本剧历史时尝试；始终可以手动选源'),
                  value: _autoEnabled,
                  onChanged: (v) async {
                    await GStorage.putSetting(
                      SettingsKeys.firstSourceAutoSelect,
                      v,
                    );
                    if (mounted) setState(() => _autoEnabled = v);
                  },
                ),
              Text(_message),
              if (_running) const LinearProgressIndicator(),
              Wrap(
                spacing: 16,
                children: [
                  if (!widget.autoSelect && !_run.cancelled)
                    FilledButton(
                      autofocus: true,
                      onPressed: _running ? null : _start,
                      child: const Text('开始检测'),
                    ),
                  OutlinedButton(
                    autofocus: widget.autoSelect,
                    onPressed: _exit,
                    child: Text(_running ? '取消并返回' : '返回手动选源'),
                  ),
                  if (!_running)
                    OutlinedButton(
                      onPressed: () async {
                        await GStorage.putSetting(
                          SettingsKeys.sourceHealthRecords,
                          '',
                        );
                        if (mounted) {
                          setState(() {
                            _stored.clear();
                            _results.clear();
                          });
                        }
                      },
                      child: const Text('清除健康记录'),
                    ),
                ],
              ),
              if (_video != null)
                SizedBox(
                  height: 180,
                  child: Video(controller: _video!, controls: NoVideoControls),
                ),
              for (final r in (_results.isEmpty
                  ? _stored.where((r) => r.subject == widget.subject.id)
                  : _results))
                ListTile(
                  title: Text('${r.rule}：${_label(r.stage)}'),
                  subtitle: Text(
                    '${r.checkedAt.toLocal()}'
                    '${r.episode.trim().isEmpty ? '' : ' · 第 ${r.episode} 集'}'
                    ' · 规则 ${r.ruleVersion} · ${_freshness(r)} · ${_reason(r.reason)}',
                  ),
                ),
            ],
          ),
        ),
      );
}
