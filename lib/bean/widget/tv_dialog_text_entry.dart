import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/tv_text_entry.dart';

/// Owns the draft of a dialog field until its closing animation unmounts it.
/// Business confirmation remains in the enclosing dialog's actions.
class TvDialogTextEntry extends StatefulWidget {
  const TvDialogTextEntry(
      {super.key, required this.title, required this.builder});

  final String title;
  final TextField Function(TextEditingController controller) builder;

  @override
  State<TvDialogTextEntry> createState() => _TvDialogTextEntryState();
}

class _TvDialogTextEntryState extends State<TvDialogTextEntry> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      TvTextEntry(title: widget.title, child: widget.builder(_controller));
}
