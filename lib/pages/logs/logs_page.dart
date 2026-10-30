import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/services/logging/logger.dart' as logging;
import 'package:kazumi/services/logging/log_export.dart';
import 'package:kazumi/services/logging/log_export_service.dart';
import 'package:kazumi/services/phone_keyboard.dart';
import 'package:kazumi/bean/widget/phone_keyboard_control.dart';

import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/bean/widget/error_widget.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key, this.phoneKeyboard, this.exportBuilder});
  final PhoneKeyboard? phoneKeyboard;
  final Future<LogExport> Function()? exportBuilder;

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final List<String> _logLines = [];
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _hasError = false;
  bool _exporting = false;
  bool _shared = false;
  int _exportGeneration = 0;
  PhoneKeyboard get _phone => widget.phoneKeyboard ?? PhoneKeyboard.instance;
  String _fullContent = '';

  static const int _initialLoadCount = 50;
  static const int _loadMoreCount = 100;
  int _displayedLines = 0;
  List<String> _allLines = [];

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _exportGeneration++;
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || _displayedLines >= _allLines.length) {
      return;
    }

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final threshold = maxScroll * 0.8;

    if (currentScroll >= threshold) {
      _loadMoreLines();
    }
  }

  Future<void> _loadLogs() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final file = await logging.getLogsPath();
      if (!mounted) return;

      if (await file.exists()) {
        final content = await logging.readRecentLogs();
        if (!mounted) return;

        _allLines = content.split('\n');
        _fullContent = content;

        final initialCount = _allLines.length < _initialLoadCount
            ? _allLines.length
            : _initialLoadCount;

        setState(() {
          _logLines.clear();
          _logLines.addAll(_allLines.take(initialCount));
          _displayedLines = initialCount;
          _isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  void _loadMoreLines() {
    if (_displayedLines >= _allLines.length) {
      return;
    }

    Future.microtask(() {
      if (!mounted) return;

      final remainingLines = _allLines.length - _displayedLines;
      final linesToLoad =
          remainingLines < _loadMoreCount ? remainingLines : _loadMoreCount;

      final newLines = _allLines.skip(_displayedLines).take(linesToLoad);

      setState(() {
        _logLines.addAll(newLines);
        _displayedLines += linesToLoad;
      });
    });
  }

  Future<void> _clearLogs() async {
    _exportGeneration++;
    _phone.session?.revokeLogExport();
    try {
      if (!await logging.clearLogs()) throw StateError('日志清除失败');
      if (!mounted) return;

      setState(() {
        _logLines.clear();
        _allLines.clear();
        _fullContent = '';
        _displayedLines = 0;
        _shared = false;
      });
    } catch (e) {
      if (!mounted) return;
      KazumiDialog.showToast(message: '清空失败: $e');
    }
  }

  Future<void> _copyLogs() async {
    try {
      await Clipboard.setData(ClipboardData(text: _fullContent));
      if (!mounted) return;
      KazumiDialog.showToast(message: '已复制到剪贴板');
    } catch (e) {
      if (!mounted) return;
      KazumiDialog.showToast(message: '复制失败: $e');
    }
  }

  Future<void> _exportToPhone() async {
    if (_exporting) return;
    final generation = ++_exportGeneration;
    setState(() => _exporting = true);
    try {
      if (_phone.uri == null || _phone.onlineCount == 0) {
        await showDialog<void>(
            context: context, builder: (_) => const PhoneKeyboardDialog());
      }
      if (!mounted) return;
      final session = _phone.session;
      if (session == null || session.isClosed || session.uri == null) {
        KazumiDialog.showToast(message: '请先开启手机遥控连接');
        return;
      }
      final snapshot = await (widget.exportBuilder ?? createLogExport)();
      if (!mounted ||
          generation != _exportGeneration ||
          !identical(session, _phone.session) ||
          session.isClosed) {
        return;
      }
      session.publishLogExport(snapshot);
      setState(() => _shared = true);
      KazumiDialog.showToast(message: '手机遥控页 → 问题反馈与日志，可预览、复制或下载；5 分钟内有效');
    } catch (_) {
      if (mounted) KazumiDialog.showToast(message: '日志导出失败，请重试');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        title: const Text('日志'),
        actions: [
          if (_shared)
            TextButton(
                onPressed: () {
                  _exportGeneration++;
                  _phone.session?.revokeLogExport();
                  setState(() => _shared = false);
                },
                child: const Text('停止导出')),
          TextButton.icon(
            onPressed: _exporting ? null : _exportToPhone,
            icon: const Icon(Icons.send_to_mobile_rounded),
            label: Text(_exporting ? '正在准备…' : '手机导出'),
          ),
        ],
      ),
      body: buildBody,
      floatingActionButton: buildFloatingButtons,
    );
  }

  Widget get buildBody {
    if (_isLoading) {
      return const Center(
        child: LoadingIndicator(),
      );
    }

    if (_hasError) {
      return GeneralErrorWidget(
        title: '无法读取日志',
        errMsg: '请稍后重新加载。',
        icon: Icons.receipt_long_rounded,
        onRetry: _loadLogs,
      );
    }

    if (_logLines.isEmpty) {
      return const GeneralEmptyState(
        icon: Icons.receipt_long_rounded,
        title: '还没有日志记录',
      );
    }

    return SelectionArea(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: MediaQuery.of(context).size.width.clamp(600, double.infinity),
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16.0),
            shrinkWrap: false,
            itemCount: _logLines.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Text(
                  _logLines[index],
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget get buildFloatingButtons {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FloatingActionButton(
          heroTag: null,
          onPressed: _clearLogs,
          tooltip: '清空日志',
          child: const Icon(Icons.clear_all),
        ),
        const SizedBox(width: 15),
        FloatingActionButton(
          heroTag: null,
          onPressed: _copyLogs,
          tooltip: '复制日志',
          child: const Icon(Icons.copy),
        ),
      ],
    );
  }
}
