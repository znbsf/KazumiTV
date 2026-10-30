import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/widget/phone_keyboard_control.dart';
import 'package:kazumi/bean/widget/phone_keyboard_target.dart';
import 'package:kazumi/bean/widget/tv_text_editing_shortcuts.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

/// An already-open editor: keep its native keyboard and outer action buttons.
/// Phone confirmation acknowledges the draft, never executes a business action.
class TvExplicitTextField extends StatelessWidget {
  const TvExplicitTextField(
      {super.key, required this.label, required this.child});
  final String label;
  final TextField child;

  @override
  Widget build(BuildContext context) {
    final editor = TvTextEditingShortcuts(child: child);
    if (!TvMode.enabled ||
        child.enabled == false ||
        child.readOnly ||
        child.obscureText ||
        RegExp(r'password|token|secret|密码|密钥|口令', caseSensitive: false)
            .hasMatch(label)) return editor;
    assert(child.controller != null);
    return PhoneKeyboardEditorTarget(
      controller: child.controller!,
      label: label,
      detachOnConfirm: false,
      maxLength: child.maxLength != null && child.maxLength! > 0
          ? child.maxLength!
          : 2048,
      inputFormatters: [
        if (child.maxLines == 1)
          FilteringTextInputFormatter.singleLineFormatter,
        ...?child.inputFormatters,
      ],
      onChanged: child.onChanged,
      onConfirm: () {},
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        editor,
        const Align(
            alignment: Alignment.centerRight, child: PhoneKeyboardButton()),
      ]),
    );
  }
}
