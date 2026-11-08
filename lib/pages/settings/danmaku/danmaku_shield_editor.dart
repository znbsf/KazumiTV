import 'package:kazumi/bean/widget/tv_text_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

import 'package:kazumi/bean/widget/content_section.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/pages/my/my_controller.dart';

class DanmakuShieldEditor extends StatefulWidget {
  const DanmakuShieldEditor({
    super.key,
    required this.controller,
    this.padding = const EdgeInsets.fromLTRB(24, 0, 24, 24),
  });

  final MyController controller;
  final EdgeInsetsGeometry padding;

  @override
  State<DanmakuShieldEditor> createState() => _DanmakuShieldEditorState();
}

class _DanmakuShieldEditorState extends State<DanmakuShieldEditor> {
  MyController get myController => widget.controller;
  final TextEditingController textEditingController = TextEditingController();
  final _entryFocus = FocusNode(debugLabel: 'Shield rule entry');
  final _ruleFocus = <String, FocusNode>{};

  FocusNode _focusFor(String rule) => _ruleFocus.putIfAbsent(
      rule, () => FocusNode(debugLabel: 'Shield rule $rule'));

  void _disposeRemovedFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final removed = _ruleFocus.keys
          .where((rule) => !myController.shieldList.contains(rule))
          .toList();
      for (final rule in removed) {
        _ruleFocus.remove(rule)?.dispose();
      }
    });
  }

  Future<void> _removeRule(String rule) async {
    final index = myController.shieldList.indexOf(rule);
    final removed = await myController.removeShieldList(rule);
    if (!mounted || !removed || !TvMode.enabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final rules = myController.shieldList;
      final target = rules.isEmpty
          ? _entryFocus
          : _focusFor(rules[index.clamp(0, rules.length - 1)]);
      target.requestFocus();
      if (target.context != null) Scrollable.ensureVisible(target.context!);
    });
  }

  @override
  void dispose() {
    textEditingController.dispose();
    _entryFocus.dispose();
    for (final node in _ruleFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _addRule() async {
    final rule = textEditingController.text.trim();
    if (rule.isEmpty) return;
    final added = await myController.addShieldList(rule);
    if (mounted && added && textEditingController.text.trim() == rule) {
      textEditingController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: widget.padding,
      children: [
        ContentSection(
          title: '添加规则',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TvTextEntry(
                child: TextField(
              controller: textEditingController,
              focusNode: TvMode.enabled ? _entryFocus : null,
              decoration: InputDecoration(
                hintText: '关键词或 /正则表达式/',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                suffixIcon: IconButton(
                  tooltip: '添加规则',
                  onPressed: _addRule,
                  icon: const Icon(Icons.add_rounded),
                ),
              ),
              onSubmitted: (_) => _addRule(),
            )),
            const SizedBox(height: 8),
            Text('包含关键词的弹幕会被隐藏。用 / / 包裹正则表达式。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
          ]),
        ),
        const SizedBox(height: 24),
        Observer(builder: (context) {
          final rules = myController.shieldList.toList();
          _disposeRemovedFocus();
          if (rules.isEmpty) {
            return const GeneralEmptyState(
              icon: Icons.filter_alt_off_rounded,
              title: '还没有屏蔽规则',
              compact: true,
            );
          }
          return ContentSection.group(
            title: '已添加 · ${rules.length}',
            children: [
              for (final rule in rules)
                ListTile(
                  key: ValueKey(rule),
                  title: Text(rule),
                  subtitle: rule.startsWith('/') && rule.endsWith('/')
                      ? const Text('正则表达式')
                      : null,
                  trailing: IconButton(
                    focusNode: TvMode.enabled ? _focusFor(rule) : null,
                    tooltip: '删除规则',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => _removeRule(rule),
                  ),
                ),
            ],
          );
        }),
      ],
    );
  }
}
