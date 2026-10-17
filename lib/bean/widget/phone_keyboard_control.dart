import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:kazumi/services/phone_keyboard.dart';

class PhoneKeyboardButton extends StatelessWidget {
  const PhoneKeyboardButton({super.key});
  @override
  Widget build(BuildContext context) => TextButton.icon(
      icon: const Icon(Icons.phonelink_ring),
      label: const Text('手机键盘'),
      onPressed: () => showDialog<void>(
          context: context, builder: (_) => const PhoneKeyboardDialog()));
}

class PhoneKeyboardDialog extends StatelessWidget {
  const PhoneKeyboardDialog({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: PhoneKeyboard.instance,
      builder: (context, _) {
        final keyboard = PhoneKeyboard.instance;
        final url = keyboard.uri?.toString();
        return AlertDialog(
            title: const Text('手机键盘'),
            scrollable: true,
            content: SizedBox(
                width: 520,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('手机与电视连接同一局域网。开启后扫码或输入完整地址；返回电视打开普通输入框即可连续输入。'),
                  if (url != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                        width: 220,
                        height: 220,
                        child: QrImageView(
                            data: url, backgroundColor: Colors.white)),
                    const SizedBox(height: 8),
                    SelectableText(url),
                    const Text('返回后连接继续；闲置 10 分钟或应用进入后台自动断开。'),
                  ] else if (keyboard.error != null)
                    Text(keyboard.error!),
                  if (keyboard.starting) const CircularProgressIndicator(),
                ])),
            actions: [
              TextButton(
                  autofocus: true,
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('返回编辑')),
              if (url == null)
                FilledButton(
                    onPressed:
                        keyboard.starting ? null : () => keyboard.start(),
                    child: const Text('开启临时连接')),
              if (url != null)
                FilledButton(
                    onPressed: keyboard.disconnect, child: const Text('断开连接')),
            ]);
      });
}
