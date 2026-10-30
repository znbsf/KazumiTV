import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/tv_text_entry.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

/// Phone confirmation edits the draft; searching remains an explicit action.
class SourceKeywordDialog extends StatefulWidget {
  const SourceKeywordDialog(
      {super.key,
      required this.initialKeyword,
      required this.sourceName,
      required this.onSubmit,
      required this.onCancel});
  final String initialKeyword, sourceName;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  @override
  State<SourceKeywordDialog> createState() => _SourceKeywordDialogState();
}

class _SourceKeywordDialogState extends State<SourceKeywordDialog> {
  late final _controller = TextEditingController(text: widget.initialKeyword);

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) widget.onSubmit(value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('修改检索词'),
        content: TvTextEntry(
          title: '检索关键词',
          child: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: '检索关键词',
              helperText: '仅检索来源：${widget.sourceName}',
              helperMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
            // TV editor confirmation saves a draft, just like phone confirm.
            // The outer search button owns the source search action.
            onSubmitted: TvMode.enabled ? null : (_) => _submit(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: widget.onCancel,
              child: Text('取消',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.outline))),
          TextButton(onPressed: _submit, child: const Text('检索')),
        ],
      );
}
