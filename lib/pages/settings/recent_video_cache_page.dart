import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/services/player/recent_video_cache_service.dart';

class RecentVideoCachePage extends StatefulWidget {
  const RecentVideoCachePage({super.key, this.service});
  final RecentVideoCacheService? service;
  @override
  State<RecentVideoCachePage> createState() => _RecentVideoCachePageState();
}

class _RecentVideoCachePageState extends State<RecentVideoCachePage> {
  late final service = widget.service ?? RecentVideoCacheService.shared;
  List<Map<String, dynamic>> entries = [];
  bool busy = false;
  String? error;
  late bool enabled = service.automaticEnabled;
  late int capacity = service.limitGiB;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await service.list();
      if (mounted) setState(() => entries = result);
    } catch (_) {
      if (mounted) setState(() => error = '读取缓存失败，请重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _delete(Map<String, dynamic>? entry) async {
    final metadata = entry?['metadata'] as Map?;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(entry == null ? '清理近期视频缓存？' : '删除这一集的缓存？'),
              content: Text(entry == null
                  ? '清理未在播放的视频及旧版附带数据。独立弹幕缓存和手动下载保留。'
                  : '${metadata?['title']} · ${metadata?['episodeTitle']}\n视频与旧版附带数据将删除；独立弹幕缓存保留。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('删除')),
              ],
            ));
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      await service.clear(id: entry?['id'] as String?);
      if (mounted) await _refresh();
    } catch (_) {
      if (mounted)
        setState(() {
          error = '清理失败，请重试';
          busy = false;
        });
    }
  }

  void _play(Map<String, dynamic> entry) {
    final meta = Map<String, dynamic>.from(entry['metadata'] as Map);
    final title = meta['title'] as String;
    final number = meta['episode'] as int;
    final road = meta['road'] as int;
    final bangumi = BangumiItem(
        id: meta['bangumiId'] as int,
        type: 2,
        name: title,
        nameCn: title,
        summary: '',
        airDate: '',
        airWeekday: 0,
        rank: 0,
        images: {},
        tags: [],
        alias: [],
        ratingScore: 0,
        votes: 0,
        votesCount: [],
        info: '');
    context.pushNamed('/video/',
        arguments: OfflineVideoPlaybackArgs(
          bangumiItem: bangumi,
          pluginName: meta['pluginName'] as String,
          episodeNumber: number,
          road: road,
          recentCacheId: entry['id'] as String,
          downloadedEpisodes: [
            DownloadEpisode(
                number,
                meta['episodeTitle'] as String,
                road,
                DownloadStatus.completed,
                100,
                entry['total'] as int,
                entry['saved'] as int,
                '',
                '',
                '',
                null,
                '',
                entry['bytes'] as int,
                '')
          ],
        ));
  }

  String _size(int bytes) => bytes >= 1024 * 1024 * 1024
      ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';

  @override
  Widget build(BuildContext context) {
    final used =
        entries.fold<int>(0, (sum, entry) => sum + (entry['bytes'] as int));
    return SettingsDetailScaffold(
        title: const Text('近期视频缓存'),
        body: SettingsList(sections: [
          SettingsSection(title: const Text('自动保留'), tiles: [
            SettingsTile.switchTile(
                leading: Icons.save_alt_rounded,
                title: const Text('自动缓存观看视频（实验功能）'),
                description: const Text('下次打开视频生效。隐身模式不自动缓存；关闭后仍可播放已保存内容。'),
                initialValue: enabled,
                onToggle: (value) async {
                  final next = value ?? !enabled;
                  await service.setEnabled(next);
                  if (mounted) setState(() => enabled = next);
                }),
            SettingsTile(
                leading: Icons.storage_rounded,
                title: const Text('容量上限'),
                description:
                    const Text('为系统至少保留 1 GiB；空间不足时停止新增缓存。正在播放的内容稍后清理。'),
                trailing: DropdownButton<int>(
                    value: capacity,
                    items: [1, 2, 4, 8]
                        .map((v) =>
                            DropdownMenuItem(value: v, child: Text('$v GiB')))
                        .toList(),
                    onChanged: busy
                        ? null
                        : (value) async {
                            if (value == null) return;
                            await service.setLimitGiB(value);
                            if (!mounted) return;
                            setState(() => capacity = value);
                            await _refresh();
                          })),
            SettingsTile(
                leading: Icons.info_outline,
                title: Text('已占用 ${_size(used)} / $capacity GiB'),
                description: const Text(
                    '按最近使用时间淘汰旧剧集，包含旧版附带数据及少量管理预留，独立弹幕缓存另计容量。只保存已请求的分片，不自动补齐跳过的部分。')),
            SettingsTile(
                leading: Icons.delete_outline,
                title: const Text('清理全部近期缓存'),
                description: const Text('保留手动下载和正在播放的缓存'),
                onPressed: busy ? null : (_) => _delete(null)),
            SettingsTile(
                leading: Icons.refresh,
                title: Text(busy ? '正在读取…' : '刷新缓存列表'),
                description: error == null ? null : Text(error!),
                onPressed: busy ? null : (_) => _refresh()),
          ]),
          SettingsSection(title: const Text('已保存剧集'), tiles: [
            if (entries.isEmpty)
              const SettingsTile(
                  leading: Icons.video_library_outlined,
                  title: Text('暂无近期缓存'),
                  description: Text('开启后，支持的点播视频会随播放保存。')),
            for (final entry in entries) _entry(entry),
          ]),
          const SettingsSection(title: Text('当前支持范围'), tiles: [
            SettingsTile(
                leading: Icons.help_outline,
                title: Text('MP4 与 HLS 点播'),
                description: Text(
                    '支持完整 MP4、单轨 HLS（含 AES-128、初始化片段和未加密字节范围），支持 HTTP 代理。缓存保留原片段，去广告由播放器执行。仅收到全部所需内容后可离线播放；跳过或中断的内容不会标为完整。\n直播、多轨/多清晰度、DRM 和加密字节范围沿用原播放方式。视频完整时优先本地；弹幕使用独立缓存策略，可在弹幕缓存设置中管理。')),
          ]),
        ]));
  }

  Widget _entry(Map<String, dynamic> entry) {
    final meta = entry['metadata'] as Map;
    final complete = entry['complete'] == true;
    final active = entry['active'] == true;
    return SettingsTile(
        leading: complete ? Icons.offline_pin_outlined : Icons.timelapse,
        title: Text('${meta['title']} · ${meta['episodeTitle']}'),
        description: Text(
            '${complete ? '可离线播放' : '部分缓存 ${entry['saved']}/${entry['total']} 段'} · ${_size(entry['bytes'] as int)}${active ? ' · 正在使用' : ''}'),
        trailing: Wrap(spacing: 8, children: [
          if (complete)
            TextButton(
                onPressed: busy ? null : () => _play(entry),
                child: const Text('本地播放')),
          TextButton(
              onPressed: busy || active ? null : () => _delete(entry),
              child: const Text('删除这一集')),
        ]));
  }
}
