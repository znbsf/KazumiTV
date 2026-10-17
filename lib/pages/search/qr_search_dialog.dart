import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:kazumi/services/qr_search_session.dart';

class QrSearchDialog extends StatefulWidget {
  const QrSearchDialog({super.key, this.sessionFactory});
  final QrSearchSession Function(void Function(String), void Function())?
      sessionFactory;
  @override
  State<QrSearchDialog> createState() => _QrSearchDialogState();
}

class _QrSearchDialogState extends State<QrSearchDialog>
    with WidgetsBindingObserver {
  late final QrSearchSession _session;
  String? _url;
  String? _error;
  String? _query;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    void received(String value) {
      if (mounted) setState(() => _query = value);
    }

    void closed() {
      if (mounted && _query == null) {
        setState(() {
          _url = null;
          _error = '会话已过期，请退出后重新扫码';
        });
      }
    }

    _session = widget.sessionFactory?.call(received, closed) ??
        QrSearchSession(onQuery: received, onClosed: closed);
    _start();
  }

  Future<void> _start() async {
    try {
      final uri = await _session.start();
      if (mounted) setState(() => _url = uri.toString());
    } catch (_) {
      if (mounted) setState(() => _error = '无法开启局域网输入，请检查电视网络后重试');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_session.close());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_session.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('手机扫码输入'),
        scrollable: true,
        content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_query != null) ...[
                const Icon(Icons.check_circle_outline, size: 48),
                const SizedBox(height: 12),
                Text('已收到：$_query'),
                const Text('按“搜索”开始查找'),
              ] else if (_error != null)
                Text(_error!)
              else if (_url == null)
                const CircularProgressIndicator()
              else ...[
                const Text('手机与电视连接同一局域网，扫码输入关键词'),
                const SizedBox(height: 12),
                SizedBox(
                    width: 220,
                    height: 220,
                    child: QrImageView(
                        data: _url!, size: 220, backgroundColor: Colors.white)),
                const SizedBox(height: 12),
                const Text('3 分钟内有效 · 最多 120 字\n退出或电视进入后台后立即关闭'),
              ],
            ])),
        actions: [
          TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('退出')),
          if (_query != null)
            FilledButton(
                onPressed: () => Navigator.of(context).pop(_query),
                child: const Text('搜索')),
        ],
      );
}
