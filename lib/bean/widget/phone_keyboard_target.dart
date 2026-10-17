import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/services/phone_keyboard.dart';
import 'package:kazumi/services/phone_keyboard_session.dart';

/// Mount only inside an explicit editor, never around its navigation preview.
class PhoneKeyboardEditorTarget extends StatefulWidget {
  const PhoneKeyboardEditorTarget(
      {super.key,
      required this.controller,
      required this.label,
      required this.onConfirm,
      required this.child,
      this.maxLength = 2048,
      this.inputFormatters = const []});
  final TextEditingController controller;
  final String label;
  final VoidCallback onConfirm;
  final Widget child;
  final int maxLength;
  final List<TextInputFormatter> inputFormatters;
  @override
  State<PhoneKeyboardEditorTarget> createState() =>
      _PhoneKeyboardEditorTargetState();
}

class _PhoneKeyboardEditorTargetState extends State<PhoneKeyboardEditorTarget> {
  late final PhoneKeyboardTarget target;
  @override
  void initState() {
    super.initState();
    target = PhoneKeyboardTarget(
        label: widget.label,
        maxLength: widget.maxLength,
        isActive: () => mounted && ModalRoute.of(context)?.isCurrent == true,
        readValue: () {
          final value = widget.controller.value;
          final selection = value.selection.isValid
              ? value.selection
              : TextSelection.collapsed(offset: value.text.length);
          return {
            'text': value.text,
            'selection': {
              'baseOffset': selection.baseOffset,
              'extentOffset': selection.extentOffset,
            }
          };
        },
        onSelection: (base, extent) {
          final length = widget.controller.text.length;
          widget.controller.selection = TextSelection(
              baseOffset: base.clamp(0, length),
              extentOffset: extent.clamp(0, length));
        },
        onText: (text) {
          var value = TextEditingValue(
              text: text,
              selection: TextSelection.collapsed(offset: text.length));
          for (final formatter in widget.inputFormatters) {
            value = formatter.formatEditUpdate(widget.controller.value, value);
          }
          widget.controller.value = value;
        },
        onConfirm: () {
          PhoneKeyboard.instance.detach(target);
          widget.onConfirm();
        });
    widget.controller.addListener(_changed);
    PhoneKeyboard.instance.attach(target);
  }

  void _changed() {
    target.revision++;
  }

  @override
  void dispose() {
    PhoneKeyboard.instance.detach(target);
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
