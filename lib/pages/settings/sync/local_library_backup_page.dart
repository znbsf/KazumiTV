import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/pages/settings/sync/sync_settings_widgets.dart';
import 'package:kazumi/services/storage/local_library_backup.dart';

class LocalLibraryBackupPage extends StatefulWidget {
  const LocalLibraryBackupPage({super.key, this.service});

  final LocalLibraryBackupService? service;

  @override
  State<LocalLibraryBackupPage> createState() => _LocalLibraryBackupPageState();
}

class _LocalLibraryBackupPageState extends State<LocalLibraryBackupPage> {
  late final LocalLibraryBackupService _service =
      widget.service ?? LocalLibraryBackupService();
  List<LocalLibraryBackupFile> _files = [];
  LocalLibraryBackupPreview? _preview;
  LocalLibraryBackupReadCancellation? _reading;
  bool _busy = false;
  bool _failed = false;
  String? _message;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _generation++;
    _reading?.cancel();
    if (_preview != null) _service.cancelPreview(_preview!);
    _service.forgetUndo();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final files = await _service.listLocal();
      if (mounted) setState(() => _files = files);
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = '无法读取本地备份列表，请检查设备存储后重试。';
        });
      }
    }
  }

  Future<void> _run(String progress, Future<void> Function() action) async {
    if (_busy) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _failed = false;
      _message = progress;
    });
    try {
      await action();
    } on LocalLibraryBackupException catch (error) {
      if (mounted && generation == _generation) {
        _failed = error.code != 'cancelled';
        _message = error.message;
        if (error.code == 'changed' || error.code == 'expired') {
          if (_preview != null) _service.cancelPreview(_preview!);
          _preview = null;
        }
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        _failed = true;
        _message = '操作未完成，请检查文件提供器和设备存储后重试。';
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _reading = null;
        });
      }
    }
  }

  void _cancelReading() {
    _generation++;
    _reading?.cancel();
    setState(() {
      _reading = null;
      _busy = false;
      _failed = false;
      _message = '已取消读取，收藏与历史未改动。';
    });
  }

  void _cancelPreview() {
    if (_preview != null) _service.cancelPreview(_preview!);
    setState(() {
      _preview = null;
      _failed = false;
      _message = '已取消恢复，收藏与历史未改动。';
    });
  }

  Future<void> _import() => _run('请选择备份文件…', () async {
        final result = await FilePicker.platform.pickFiles(
          dialogTitle: '选择收藏与历史备份',
          type: FileType.any,
          allowMultiple: false,
          withData: false,
          withReadStream: true,
        );
        if (!mounted) return;
        if (result == null || result.files.isEmpty) {
          _message = '已取消文件选择，收藏与历史未改动。';
          return;
        }
        final file = result.files.single;
        if (file.size > LocalLibraryArchiveCodec.maxBytes) {
          throw const LocalLibraryBackupException('tooLarge', '备份超过大小限制。');
        }
        final stream = file.readStream ??
            (file.path == null ? null : File(file.path!).openRead());
        if (stream == null) {
          throw const LocalLibraryBackupException(
              'missing', '文件提供器未返回可读取的文件，请重新选择。');
        }
        final cancellation = LocalLibraryBackupReadCancellation();
        setState(() {
          _reading = cancellation;
          _message = '正在读取并校验备份…';
        });
        final preview =
            await _service.previewStream(stream, cancellation: cancellation);
        if (!mounted || cancellation.isCancelled) {
          _service.cancelPreview(preview);
          return;
        }
        _preview = preview;
        _message = null;
      });

  Future<void> _previewLocal(LocalLibraryBackupFile file) =>
      _run('正在读取并校验本地备份…', () async {
        final cancellation = LocalLibraryBackupReadCancellation();
        setState(() => _reading = cancellation);
        final preview =
            await _service.previewLocal(file, cancellation: cancellation);
        if (!mounted || cancellation.isCancelled) {
          _service.cancelPreview(preview);
          return;
        }
        _preview = preview;
        _message = null;
      });

  Future<void> _export() => _run('正在生成备份…', () async {
        final bytes = await _service.export();
        if (!mounted) return;
        final result = await FilePicker.platform.saveFile(
          dialogTitle: '导出收藏与历史备份',
          fileName:
              'KazumiFlutter-library-${DateTime.now().millisecondsSinceEpoch}.json',
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: bytes,
        );
        if (mounted) {
          _message = result == null ? '已取消导出。' : '已导出收藏与历史备份。';
        }
      });

  Future<void> _saveLocal() => _run('正在保存本地备份…', () async {
        await _service.saveLocal();
        final files = await _service.listLocal();
        if (mounted) {
          _files = files;
          _message = '本地备份已保存。';
        }
      });

  Future<void> _confirm() {
    final preview = _preview;
    if (preview == null) return Future.value();
    return _run('正在恢复收藏与历史…', () async {
      await _service.confirm(preview);
      if (mounted) {
        _preview = null;
        _message = '恢复完成，可在本页撤销上次恢复。';
      }
    });
  }

  Future<void> _undo() => _run('正在撤销恢复…', () async {
        await _service.undo();
        if (mounted) _message = '已撤销恢复。';
      });

  String _date(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:${value.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return PopScope(
      canPop: !_busy && preview == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_reading != null) {
          _cancelReading();
        } else if (!_busy && _preview != null) {
          _cancelPreview();
        }
      },
      child: SettingsDetailScaffold(
        title: const Text('收藏与历史备份'),
        body: SyncPageBody(children: [
          const SyncPageIntro(
            icon: Icons.backup_rounded,
            title: '收藏与历史备份',
            description: '备份收藏分类、每集观看进度和播放来源。恢复前会先预览，确认后替换当前收藏与历史。',
          ),
          const Text('备份文件包含个人收藏、历史与来源信息，请妥善保管。账号凭据、资源规则和设置不在此备份中。'),
          const Text('恢复仅替换本机记录；启用 WebDAV 后会与远端合并。'),
          if (_message != null)
            SyncFeedback(message: _message!, error: _failed, busy: _busy),
          if (_reading != null)
            StateActionButton.tonal(
                onPressed: _cancelReading,
                text: '取消读取',
                icon: Icons.close_rounded),
          if (preview != null) ...[
            Semantics(
              header: true,
              child: Text(
                  '恢复预览：${preview.collectionCount} 条收藏，${preview.historyCount} 条历史',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            Text('备份时间：${_date(preview.createdAt)}'),
            const Text(
                '确认后将替换当前收藏与历史。本地备份文件会保留。本页可撤销一次恢复；离开本页后无法撤销。恢复后产生新记录会阻止撤销覆盖。'),
            for (final sample in preview.collectionSamples) Text(sample),
            for (final sample in preview.historySamples) Text(sample),
            StateActionButton(
                onPressed: _busy ? null : _confirm,
                text: '确认替换收藏与历史',
                icon: Icons.restore_rounded),
            StateActionButton.tonal(
                onPressed: _busy ? null : _cancelPreview,
                text: '取消恢复',
                icon: Icons.close_rounded),
          ] else ...[
            StateActionButton(
                onPressed: _busy ? null : _saveLocal,
                text: '保存本地备份',
                icon: Icons.save_rounded),
            const Text('最多保留 5 份本地备份，新增备份会删除最旧一份。卸载应用会删除本地备份，请导出重要备份。'),
            StateActionButton.tonal(
                onPressed: _busy ? null : _export,
                text: '导出到文件',
                icon: Icons.file_upload_rounded),
            StateActionButton.tonal(
                onPressed: _busy ? null : _import,
                text: '从文件恢复',
                icon: Icons.file_download_rounded),
            if (_service.canUndo) ...[
              StateActionButton.tonal(
                  onPressed: _busy ? null : _undo,
                  text: '撤销上次恢复',
                  icon: Icons.undo_rounded),
              const Text('撤销只在本页有效；离开本页后无法撤销。'),
            ],
            Text('本地备份', style: Theme.of(context).textTheme.titleLarge),
            if (_files.isEmpty) const Text('暂无本地备份'),
            for (final file in _files)
              StateActionButton.tonal(
                  onPressed: _busy ? null : () => _previewLocal(file),
                  text: '预览备份 · ${_date(file.createdAt)}',
                  icon: Icons.preview_rounded),
          ],
        ]),
      ),
    );
  }
}
