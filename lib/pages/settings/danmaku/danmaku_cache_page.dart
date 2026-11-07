import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/services/danmaku/danmaku_cache_service.dart';
import 'package:kazumi/services/storage/storage.dart';

class DanmakuCachePage extends StatefulWidget {
  const DanmakuCachePage({super.key, this.cache});
  final DanmakuCacheService? cache;

  @override
  State<DanmakuCachePage> createState() => _DanmakuCachePageState();
}

class _DanmakuCachePageState extends State<DanmakuCachePage> {
  late final _cache = widget.cache ?? DanmakuCacheService.shared;
  late bool _enabled = GStorage.getSetting(SettingsKeys.danmakuCacheEnabled);
  late int _limit = GStorage.getSetting(SettingsKeys.danmakuCacheMiB);
  late Future<Map<String, int>> _stats = _cache.stats();
  bool _busy = false;

  void _refresh() => setState(() => _stats = _cache.stats());

  Future<void> _clear() async {
    final confirmed = await KazumiDialog.show<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除弹幕缓存？'),
        content: const Text('同时清除缓存的番剧匹配和搜索结果，下次使用时重新获取。视频和手动下载保留。'),
        actions: [
          TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('清除')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _cache.clear();
      if (mounted) _refresh();
    } catch (_) {
      if (mounted) {
        KazumiDialog.showToast(context: context, message: '清除失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resize(int? value) async {
    if (value == null || _busy) return;
    setState(() {
      _busy = true;
      _limit = value;
    });
    try {
      await GStorage.putSetting(SettingsKeys.danmakuCacheMiB, value);
      await _cache.resize();
      if (mounted) _refresh();
    } catch (_) {
      if (mounted) {
        KazumiDialog.showToast(context: context, message: '调整缓存失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
        title: const Text('弹幕缓存'),
        body: FutureBuilder<Map<String, int>>(
          future: _stats,
          builder: (context, snapshot) => SettingsList(sections: [
            SettingsSection(
                tiles: [
                  SettingsTile.switchTile(
                    title: const Text('缓存弹幕服务数据'),
                    description:
                        const Text('独立保存弹幕、番剧匹配和搜索结果，减少重复请求。隐身模式不读写此缓存。'),
                    initialValue: _enabled,
                    onToggle: (value) async {
                      final next = value ?? !_enabled;
                      await GStorage.putSetting(
                          SettingsKeys.danmakuCacheEnabled, next);
                      if (mounted) setState(() => _enabled = next);
                    },
                  ),
                ],
                bottomInfo: const Text(
                    '弹幕和搜索结果在 6 小时内直接使用缓存，番剧匹配保留 7 天。更新失败时可使用 30 天内的旧数据；超过服务配额后暂停请求，至少等待 15 分钟。')),
            SettingsRadioSection<int>(
              title: const Text('独立容量上限'),
              groupValue: _limit,
              onChanged: _busy ? (_) {} : _resize,
              tiles: [
                for (final size in [64, 128, 256, 512, 1024])
                  SettingsTile.radioTile(
                      radioValue: size,
                      title: Text(size == 1024 ? '1 GiB' : '$size MiB'))
              ],
            ),
            SettingsSection(
                title: const Text('已保存的数据'),
                bottomInfo: const Text(
                    '压缩保存，最多 4000 条；空间不足时淘汰最近最少使用的数据。清理视频缓存不会删除这里的弹幕。'),
                tiles: [
                  SettingsTile(
                      title: Text(snapshot.hasData
                          ? '${snapshot.data!['entries']} 条 · ${(snapshot.data!['bytes']! / (1024 * 1024)).toStringAsFixed(1)} MiB'
                          : snapshot.hasError
                              ? '统计失败，点击重试'
                              : '正在统计…'),
                      leading: Icons.refresh_rounded,
                      onPressed: (_) => _refresh()),
                  SettingsTile(
                      title: const Text('清除弹幕缓存'),
                      enabled: !_busy,
                      leading: Icons.cleaning_services_rounded,
                      onPressed: (_) => _clear()),
                ]),
          ]),
        ),
      );
}
