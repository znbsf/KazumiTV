import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/tv_text_editing_shortcuts.dart';
import 'package:kazumi/bean/widget/tv_focusable_surface.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

/// TV navigation selects an action; only explicit activation opens an editor.
/// Non-TV keeps the original field, callbacks and pointer interaction intact.
class TvTextEntry extends StatefulWidget {
  const TvTextEntry({super.key, required this.child, this.title});
  final TextField child;
  final String? title;

  @override
  State<TvTextEntry> createState() => _TvTextEntryState();
}

class _TvTextEntryState extends State<TvTextEntry> {
  final _entryFocus = FocusNode(debugLabel: 'TV text entry');
  bool _opening = false;

  @override
  void dispose() {
    _entryFocus.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final field = widget.child;
    if (_opening || field.enabled == false || field.readOnly) return;
    _opening = true;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TvTextEditor(field: field, title: widget.title),
    );
    _opening = false;
    if (!mounted) return;
    (widget.child.focusNode ?? _entryFocus).requestFocus();
    if (result != null) {
      field.controller?.value = TextEditingValue(
          text: result,
          selection: TextSelection.collapsed(offset: result.length));
      field.onChanged?.call(result);
      field.onSubmitted?.call(result);
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        (widget.child.focusNode ?? _entryFocus).requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.child;
    if (!TvMode.enabled) return field;
    final decoration = field.decoration ?? const InputDecoration();
    final active = field.enabled != false && !field.readOnly;
    Widget preview() => InputDecorator(
          decoration: decoration.copyWith(
              suffixIcon: const SizedBox.shrink(), enabled: active),
          isEmpty: field.controller?.text.isEmpty ?? true,
          child: Text(
              field.obscureText
                  ? field.obscuringCharacter *
                      (field.controller?.text.length ?? 0)
                  : field.controller?.text ?? '',
              maxLines: field.maxLines,
              overflow: field.maxLines == null ? null : TextOverflow.ellipsis,
              style: field.style),
        );
    return Row(children: [
      Expanded(
          child: ExcludeFocus(
              excluding: !active,
              child: TvFocusableSurface(
                focusNode: field.focusNode ?? _entryFocus,
                autofocus: field.autofocus,
                focusScale: 1,
                onPressed: _open,
                child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: active ? _open : null,
                    child: field.controller == null
                        ? preview()
                        : ValueListenableBuilder<TextEditingValue>(
                            valueListenable: field.controller!,
                            builder: (_, __, ___) => preview())),
              ))),
      if (decoration.suffixIcon != null) decoration.suffixIcon!,
    ]);
  }
}

class _TvTextEditor extends StatefulWidget {
  const _TvTextEditor({required this.field, this.title});
  final TextField field;
  final String? title;
  @override
  State<_TvTextEditor> createState() => _TvTextEditorState();
}

class _TvTextEditorState extends State<_TvTextEditor> {
  bool _closing = false;
  void _close([String? value]) {
    if (_closing || !mounted || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _closing = true;
    Navigator.of(context).pop(value);
  }

  late final _draft =
      TextEditingController(text: widget.field.controller?.text);
  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    return AlertDialog(
      title: Text(widget.title ??
          field.decoration?.labelText ??
          field.decoration?.hintText ??
          '编辑文本'),
      scrollable: true,
      content: SizedBox(
          width: 560,
          child: TvTextEditingShortcuts(
              child: TextField(
            key: const Key('tv-text-editor'),
            controller: _draft,
            autofocus: true,
            keyboardType: field.keyboardType,
            textInputAction: field.textInputAction,
            maxLines: field.maxLines,
            minLines: field.minLines,
            maxLength: field.maxLength,
            maxLengthEnforcement: field.maxLengthEnforcement,
            obscureText: field.obscureText,
            obscuringCharacter: field.obscuringCharacter,
            autocorrect: field.autocorrect,
            enableSuggestions: field.enableSuggestions,
            inputFormatters: field.inputFormatters,
            style: field.style,
            textCapitalization: field.textCapitalization,
            decoration: (field.decoration ?? const InputDecoration())
                .copyWith(suffixIcon: const SizedBox.shrink()),
            onSubmitted: (_) => _close(_draft.text),
          ))),
      actions: [
        TextButton(onPressed: () => _close(), child: const Text('取消')),
        FilledButton(
            onPressed: () => _close(_draft.text), child: const Text('确定')),
      ],
    );
  }
}
