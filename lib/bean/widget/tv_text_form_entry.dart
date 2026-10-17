import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/widget/tv_text_entry.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

/// A controller-backed form field with an explicit TV editing boundary.
/// Native TextFormField remains the mobile implementation.
class TvTextFormEntry extends StatelessWidget {
  const TvTextFormEntry(
      {super.key,
      required this.controller,
      this.focusNode,
      this.decoration = const InputDecoration(),
      this.enabled = true,
      this.autofocus = false,
      this.obscureText = false,
      this.allowPhoneKeyboard = true,
      this.autocorrect = true,
      this.enableSuggestions = true,
      this.keyboardType,
      this.textInputAction,
      this.inputFormatters,
      this.validator,
      this.onSaved,
      this.onChanged,
      this.onFieldSubmitted,
      this.autovalidateMode = AutovalidateMode.disabled});
  final TextEditingController controller;
  final FocusNode? focusNode;
  final InputDecoration decoration;
  final bool enabled, autofocus, obscureText, autocorrect, enableSuggestions;
  final bool allowPhoneKeyboard;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final FormFieldValidator<String>? validator;
  final FormFieldSetter<String>? onSaved;
  final ValueChanged<String>? onChanged, onFieldSubmitted;
  final AutovalidateMode autovalidateMode;

  @override
  Widget build(BuildContext context) {
    if (!TvMode.enabled) {
      return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: decoration,
          enabled: enabled,
          autofocus: autofocus,
          obscureText: obscureText,
          autocorrect: autocorrect,
          enableSuggestions: enableSuggestions,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          inputFormatters: inputFormatters,
          validator: validator,
          onSaved: onSaved,
          onChanged: onChanged,
          onFieldSubmitted: onFieldSubmitted,
          autovalidateMode: autovalidateMode);
    }
    return _TvFormField(entry: this);
  }
}

class _TvFormField extends FormField<String> {
  _TvFormField({required this.entry})
      : super(
            initialValue: entry.controller.text,
            enabled: entry.enabled,
            validator: entry.validator,
            onSaved: entry.onSaved,
            autovalidateMode: entry.autovalidateMode,
            builder: (state) => TvTextEntry(
                allowPhoneKeyboard: entry.allowPhoneKeyboard,
                child: TextField(
                  controller: entry.controller,
                  focusNode: entry.focusNode,
                  decoration:
                      entry.decoration.copyWith(errorText: state.errorText),
                  enabled: entry.enabled,
                  autofocus: entry.autofocus,
                  obscureText: entry.obscureText,
                  autocorrect: entry.autocorrect,
                  enableSuggestions: entry.enableSuggestions,
                  keyboardType: entry.keyboardType,
                  textInputAction: entry.textInputAction,
                  inputFormatters: entry.inputFormatters,
                  onChanged: entry.onChanged,
                  onSubmitted: entry.onFieldSubmitted,
                )));
  final TvTextFormEntry entry;
  @override
  FormFieldState<String> createState() => _TvFormFieldState();
}

class _TvFormFieldState extends FormFieldState<String> {
  @override
  _TvFormField get widget => super.widget as _TvFormField;
  @override
  void initState() {
    super.initState();
    widget.entry.controller.addListener(_changed);
  }

  void _changed() {
    if (value != widget.entry.controller.text) {
      didChange(widget.entry.controller.text);
    }
  }

  @override
  void didUpdateWidget(covariant _TvFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.controller != widget.entry.controller) {
      oldWidget.entry.controller.removeListener(_changed);
      widget.entry.controller.addListener(_changed);
      setValue(widget.entry.controller.text);
    }
  }

  @override
  void reset() {
    // Set the controller before super.reset so reset clears interaction/error state.
    widget.entry.controller.text = widget.initialValue ?? '';
    super.reset();
    widget.entry.onChanged?.call(widget.entry.controller.text);
  }

  @override
  void dispose() {
    widget.entry.controller.removeListener(_changed);
    super.dispose();
  }
}
