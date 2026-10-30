import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/tv_explicit_text_field.dart';

/// Own the draft until the route is unmounted; cancellation never edits caller data.
class TvTextPromptDialog extends StatefulWidget {
  const TvTextPromptDialog(
      {super.key,
      required this.title,
      required this.initialText,
      required this.hint,
      required this.submitLabel});
  final String title, initialText, hint, submitLabel;
  @override
  State<TvTextPromptDialog> createState() => _TvTextPromptDialogState();
}

class _TvTextPromptDialogState extends State<TvTextPromptDialog> {
  late final _draft = TextEditingController(text: widget.initialText);
  bool _closing = false;
  void _close([String? value]) {
    if (_closing || !mounted || ModalRoute.of(context)?.isCurrent != true)
      return;
    if (value != null && value.trim().isEmpty) return;
    _closing = true;
    Navigator.of(context).pop(value);
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        scrollable: true,
        content: TvExplicitTextField(
            label: widget.title,
            child: TextField(
              controller: _draft,
              autofocus: true,
              decoration: InputDecoration(hintText: widget.hint),
              onSubmitted: _close,
            )),
        actions: [
          TextButton(onPressed: () => _close(), child: const Text('取消')),
          TextButton(
              onPressed: () => _close(_draft.text),
              child: Text(widget.submitLabel)),
        ],
      );
}
