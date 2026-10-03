import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Flutter fallback for the native browser; returns an original, 0-based index.
Future<int?> showEpisodeJumpDialog(BuildContext context,
    {required int count}) async {
  final route = DialogRoute<int>(
      context: context, builder: (context) => _EpisodeJumpDialog(count: count));
  final result = await Navigator.of(context, rootNavigator: true).push(route);
  // Restore the caller's focus only after the dialog's departing scope is gone.
  await route.completed;
  return result;
}

class _EpisodeJumpDialog extends StatefulWidget {
  const _EpisodeJumpDialog({required this.count});
  final int count;

  @override
  State<_EpisodeJumpDialog> createState() => _EpisodeJumpDialogState();
}

class _EpisodeJumpDialogState extends State<_EpisodeJumpDialog> {
  final _input = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _confirm() {
    final number = int.tryParse(_input.text);
    if (number == null || number < 1 || number > widget.count) {
      setState(() => _error = '请输入 1–${widget.count} 的原始集序号');
      return;
    }
    Navigator.pop(context, number - 1);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('定位剧集'),
        content: TextField(
          key: const ValueKey('episode-jump-number'),
          controller: _input,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: '原始集序号（1–${widget.count}）',
            errorText: _error,
          ),
          onSubmitted: (_) => _confirm(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(onPressed: _confirm, child: const Text('定位')),
        ],
      );
}
