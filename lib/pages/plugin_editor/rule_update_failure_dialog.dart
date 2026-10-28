import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/pages/plugin_editor/rule_dialogs.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';

Future<void> showRuleUpdateFailures(
  PluginsController controller, {
  required List<String> failedNames,
  required List<String> incompatibleNames,
  required String summary,
}) async {
  await KazumiDialog.show<void>(
    builder: (_) => _RuleUpdateFailureDialog(
      controller: controller,
      issues: {
        for (final name in failedNames) name: '下载或解析规则失败',
        for (final name in incompatibleNames) name: '规则需要更高版本客户端',
      },
      summary: summary,
    ),
  );
}

class _RuleUpdateFailureDialog extends StatefulWidget {
  const _RuleUpdateFailureDialog({
    required this.controller,
    required this.issues,
    required this.summary,
  });

  final PluginsController controller;
  final Map<String, String> issues;
  final String summary;

  @override
  State<_RuleUpdateFailureDialog> createState() =>
      _RuleUpdateFailureDialogState();
}

class _RuleUpdateFailureDialogState extends State<_RuleUpdateFailureDialog> {
  final _closeFocus = FocusNode();
  final _handled = <String, String>{};
  String? _busy;

  @override
  void dispose() {
    _closeFocus.dispose();
    super.dispose();
  }

  Future<void> _handle(String name, {required bool remove}) async {
    if (_busy != null) return;
    setState(() => _busy = name);
    try {
      if (remove) {
        if (!await confirmRuleDeletion(context, {name}) || !mounted) return;
        await widget.controller.removePlugins({name});
      } else {
        await widget.controller.setPluginEnabled(name, false);
      }
      if (mounted) {
        setState(() => _handled[name] = remove ? '已移除' : '已暂时停用');
      }
    } catch (_) {
      if (mounted) {
        KazumiDialog.showToast(
          context: context,
          message: '$name：${remove ? '移除' : '停用'}失败，请重试',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = null);
        _closeFocus.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('部分规则未能更新'),
        scrollable: true,
        content: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.summary),
              const SizedBox(height: 12),
              const Text('可保留原规则，或选择暂时停用、移除。暂时停用后不再参与搜索和自动更新，可在“规则管理”恢复启用。'),
              for (final issue in widget.issues.entries) ...[
                const Divider(height: 24),
                Text(issue.key, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(_handled[issue.key] ?? issue.value),
                if (!_handled.containsKey(issue.key) &&
                    widget.controller.pluginList.any(
                      (p) => pluginNameKey(p.name) == pluginNameKey(issue.key),
                    ))
                  Wrap(
                    spacing: 12,
                    children: [
                      TextButton(
                        onPressed: _busy != null ||
                                !widget.controller.isPluginEnabled(issue.key)
                            ? null
                            : () => _handle(issue.key, remove: false),
                        child: const Text('暂时停用'),
                      ),
                      TextButton(
                        onPressed: _busy != null
                            ? null
                            : () => _handle(issue.key, remove: true),
                        child: const Text('移除'),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            autofocus: true,
            focusNode: _closeFocus,
            onPressed: () => KazumiDialog.dismiss(context: context),
            child: const Text('保留并关闭'),
          ),
        ],
      );
}
