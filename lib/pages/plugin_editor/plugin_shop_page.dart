import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/widget/tv_text_entry.dart';
import 'package:kazumi/pages/plugin_editor/plugin_catalog_view.dart';
import 'package:kazumi/plugins/plugins_controller.dart';

class PluginShopPage extends StatefulWidget {
  const PluginShopPage({super.key, required this.controller});
  final PluginsController controller;
  @override
  State<PluginShopPage> createState() => _PluginShopPageState();
}

class _PluginShopPageState extends State<PluginShopPage> {
  int revision = 0;
  Future<void> configure() async {
    final changed = await showDialog<bool>(
        context: context,
        builder: (_) => _RepositoryDialog(controller: widget.controller));
    if (changed == true && mounted)
      setState(() {
        revision++;
      });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: SysAppBar(title: const Text('规则仓库'), actions: [
          IconButton(
              onPressed: configure,
              tooltip: '设置规则仓库',
              icon: const Icon(Icons.settings)),
        ]),
        body: SafeArea(
            top: false,
            child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: PluginCatalogView(
                        key: ValueKey(revision),
                        controller: widget.controller)))),
      );
}

class _RepositoryDialog extends StatefulWidget {
  const _RepositoryDialog({required this.controller});
  final PluginsController controller;
  @override
  State<_RepositoryDialog> createState() => _RepositoryDialogState();
}

class _RepositoryDialogState extends State<_RepositoryDialog> {
  late final text =
      TextEditingController(text: widget.controller.ruleRepository);
  String? error;
  bool saving = false;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> save(String value) async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final changed = await widget.controller.setRuleRepository(value);
      if (mounted) Navigator.of(context).pop(changed);
    } catch (e) {
      if (mounted)
        setState(() {
          error = '$e';
          saving = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('设置规则仓库'),
        scrollable: true,
        content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('仅使用你信任的规则仓库。切换后，目录、安装和更新将使用新仓库；已安装规则会保留。'),
              const SizedBox(height: 16),
              TvTextEntry(
                  title: '规则仓库地址',
                  child: TextField(
                      controller: text,
                      enabled: !saving,
                      decoration: InputDecoration(
                          labelText: '目录或 index.json URL',
                          errorText: error,
                          errorMaxLines: 4))),
            ])),
        actions: [
          TextButton(
              onPressed: saving ? null : () => Navigator.of(context).pop(false),
              child: const Text('取消')),
          TextButton(
              onPressed: saving ? null : () => save(''),
              child: const Text('恢复官方')),
          FilledButton(
              onPressed: saving ? null : () => save(text.text),
              child: Text(saving ? '保存中' : '保存')),
        ],
      );
}
