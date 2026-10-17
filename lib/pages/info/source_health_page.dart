import 'package:kazumi/services/source_health/source_health_preferences.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kazumi/utils/date_time.dart' show formatDateTime;
import 'package:kazumi/bean/widget/tv_focusable_surface.dart';
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
  bool _globalEnabled = true;
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
    _globalEnabled = GStorage.getSetting(SettingsKeys.sourceHealthGlobal);
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
    _stored = HealthRecordCodec.merge(_stored, record);
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
    var resolving = true;
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
      resolving = false;
      final androidConfiguration = Platform.isAndroid
          ? resolveAndroidVideoConfiguration(
              configuredOutput: GStorage.getSetting(
                SettingsKeys.androidVideoRenderer,
              ),
              isTv: TvMode.enabled,
              hardwareAcceleration: GStorage.getSetting(SettingsKeys.hAenable),
              hardwareDecoder:
                  GStorage.getSetting(SettingsKeys.hardwareDecoder),
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
          enableHardwareAcceleration:
              androidConfiguration?.hardwareAcceleration ??
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
    } on HealthCancelled {
      rethrow;
    } on CaptchaRequiredException {
      rethrow;
    } on HealthPlaybackFailure {
      rethrow;
    } on TimeoutException {
      rethrow;
    } catch (_) {
      throw HealthPlaybackFailure(resolving ? 'parse_failed' : 'player_failed');
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
              useGlobal: _globalEnabled,
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
    final matching = widget.plugins.where((p) => p.name == record.rule);
    if (matching.isEmpty) return '规则未加载，仅保留历史';
    if (ruleFingerprint(matching.first) != record.fingerprint) {
      return '规则已变化，仅保留旧版本历史';
    }
    if (record.checkedAt.isAfter(DateTime.now())) return '记录时间异常，需复验';
    if (record.environment != _environment) return '播放环境已变化，仅作站点历史参考';
    return switch (record.freshnessBand(DateTime.now())) {
      0 => '近期记录，播放仍需确认',
      1 => '较旧记录，待复验',
      _ => '历史记录，待复验',
    };
  }

  List<HealthRecord> get _visibleRecords {
    var records = List<HealthRecord>.of(_stored);
    for (final r in _results) {
      records = HealthRecordCodec.merge(records, r);
    }
    return records
        .where((r) => _globalEnabled || r.subject == widget.subject.id)
        .toList();
  }

  String _recordTime(DateTime value) {
    final local = value.toLocal();
    return '${formatDateTime(local)} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _recordSummary(HealthRecord r) => '${_recordTime(r.checkedAt)}'
      '${r.episode.trim().isEmpty ? '' : ' · 第 ${r.episode} 集'}'
      ' · ${_freshness(r).replaceAll('，仅保留历史', '').replaceAll('，仅保留旧版本历史', '').replaceAll('，仅作站点历史参考', '').replaceAll('，播放仍需确认', '')}';

  String _recordText(HealthRecord r) => '${_recordTime(r.checkedAt)}'
      '${r.episode.trim().isEmpty ? '' : ' · 第 ${r.episode} 集'}'
      ' · 规则 ${r.ruleVersion} · ${_freshness(r)} · ${_reason(r.reason)}';

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
        'no_search_results' => '本番剧未命中，不代表其他番剧不可用',
        'request_failed' => '站点请求失败',
        'parse_failed' => '媒体解析失败',
        'player_failed' => '播放器验证失败',
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
          appBar: AppBar(title: Text(widget.autoSelect ? '显式有限检测' : '源健康检测')),
          body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.subject.nameCn.isEmpty
                        ? widget.subject.name
                        : widget.subject.nameCn,
                    style: TvVisuals.control,
                  ),
                  const Text('检测首帧不代表后续完整播放成功，正式播放仍可能因网络变化失败，可手动换源。'),
                  const Text(
                    '显式检测最多 12 个 / 3 分钟。历史成功保留，随时间降低优先级；规则变化后旧证据仅供查看。开始观看只复用成功记录，无记录或失败时自动搜索番剧并手动选源，不自动检测。单部成功不代表全站可用。',
                  ),
                  if (!widget.autoSelect)
                    SwitchListTile(
                      title: const Text('使用成功记录开始观看'),
                      subtitle: const Text('只尝试一个有成功记录的源；无记录或失败时手动选择'),
                      value: _autoEnabled,
                      onChanged: (v) async {
                        await GStorage.putSetting(
                          SettingsKeys.firstSourceAutoSelect,
                          v,
                        );
                        if (mounted) setState(() => _autoEnabled = v);
                      },
                    ),
                  if (!widget.autoSelect)
                    SwitchListTile(
                      key: const ValueKey('health-global'),
                      title: const Text('将成功记录用于所有番剧'),
                      subtitle: const Text('其他番剧优先尝试记录源，仍重新匹配自己的资源；单剧手选优先'),
                      value: _globalEnabled,
                      onChanged: _running
                          ? null
                          : (value) async {
                              await GStorage.putSetting(
                                  SettingsKeys.sourceHealthGlobal, value);
                              if (mounted) {
                                setState(() => _globalEnabled = value);
                              }
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
                      child:
                          Video(controller: _video!, controls: NoVideoControls),
                    ),
                  if (_visibleRecords.isEmpty) const Text('暂无检测记录'),
                  for (final r in _visibleRecords)
                    _HealthRecordTile(
                      key: ValueKey(
                          '${r.subject}|${r.rule}|${r.fingerprint}|${r.environment}'),
                      record: r,
                      title: '${r.rule}：${_label(r.stage)}',
                      subtitle: _recordSummary(r),
                      detail:
                          '番剧 ID：${r.subject}\n最近尝试：${_label(r.stage)}\n${_recordText(r)}'
                          '${r.success == null ? '' : '\n\n历史成功：${_recordText(r.success!)}'}',
                    ),
                ],
              )),
        ),
      );
}

class _HealthRecordTile extends StatefulWidget {
  const _HealthRecordTile(
      {super.key,
      required this.record,
      required this.title,
      required this.subtitle,
      required this.detail});
  final HealthRecord record;
  final String title, subtitle, detail;
  @override
  State<_HealthRecordTile> createState() => _HealthRecordTileState();
}

class _HealthRecordTileState extends State<_HealthRecordTile> {
  late final FocusNode _focus =
      FocusNode(debugLabel: 'health-record-${widget.record.rule}');
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _details() async {
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(widget.title),
              content: SingleChildScrollView(child: Text(widget.detail)),
              actions: [
                TextButton(
                    autofocus: true,
                    onPressed: () => Navigator.pop(context),
                    child: const Text('返回记录'))
              ],
            ));
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      _focus.requestFocus();
    }
  }

  void _focusChanged(bool focused) {
    if (!focused) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focus.hasFocus) return;
      // Include the outer margin so the focus outline is not flush with the
      // viewport edge when the last record scrolls into view.
      Scrollable.ensureVisible(context,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: TvFocusableSurface(
          enabled: true,
          focusNode: _focus,
          focusScale: 1,
          ensureVisibleOnFocus: false,
          onFocusChange: _focusChanged,
          onPressed: _details,
          child: ListTile(
              onTap: _details,
              title: Text(widget.title),
              subtitle: Text(widget.subtitle),
              trailing: const Icon(Icons.chevron_right)),
        ),
      );
}
