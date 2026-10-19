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

class PhoneKeyboardDialog extends StatefulWidget {
  const PhoneKeyboardDialog({super.key});
  @override
  State<PhoneKeyboardDialog> createState() => _PhoneKeyboardDialogState();
}

class _PhoneKeyboardDialogState extends State<PhoneKeyboardDialog> {
  bool _remember = true;
  bool _closing = false;
  bool _waitingForConnection = false;
  void _connectionChanged() {
    if (!_waitingForConnection ||
        _closing ||
        PhoneKeyboard.instance.session?.clientConnected != true) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      } else {
        _closing = false;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    PhoneKeyboard.instance.enterControlDialog();
    _waitingForConnection =
        PhoneKeyboard.instance.session?.clientConnected != true;
    PhoneKeyboard.instance.addListener(_connectionChanged);
  }

  @override
  void dispose() {
    PhoneKeyboard.instance.removeListener(_connectionChanged);
    PhoneKeyboard.instance.leaveControlDialog();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: PhoneKeyboard.instance,
      builder: (context, _) {
        final keyboard = PhoneKeyboard.instance;
        final url = keyboard.uri?.toString();
        final count = keyboard.onlineCount;
        return AlertDialog(
            title: const Text('手机遥控与键盘'),
            scrollable: true,
            content: SizedBox(
                width: 520,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('手机与电视连接同一局域网，扫码后即可遥控或输入。'),
                  const SizedBox(height: 12),
                  Text(
                      url != null
                          ? count > 0
                              ? '已连接 $count 个遥控端'
                              : '等待手机连接 · 当前 0 个在线'
                          : keyboard.isPaused
                              ? '遥控已暂停 · 当前 0 个在线'
                              : '遥控未开启 · 当前 0 个在线',
                      style: Theme.of(context).textTheme.titleMedium),
                  Text('按浏览器统计；关页、锁屏或断网后约 12 秒更新。',
                      style: Theme.of(context).textTheme.bodySmall),
                  if (url == null && !keyboard.hasPairing)
                    SwitchListTile(
                      title: const Text('保留配对 7 天'),
                      subtitle:
                          const Text('重新打开电视应用后可用原手机页面连接；电视 IP 改变时需重新扫码。'),
                      value: _remember,
                      onChanged: keyboard.starting
                          ? null
                          : (value) => setState(() => _remember = value),
                    ),
                  if (keyboard.hasPairing)
                    Text(
                        '配对有效至 ${keyboard.pairingExpiresAt!.toLocal().toString().substring(0, 16)}${keyboard.isPaused ? " · 请点击恢复连接" : ""}'),
                  if (url != null) ...[
                    const SizedBox(height: 12),
                    Row(children: [
                      SizedBox(
                          width: 160,
                          height: 160,
                          child: QrImageView(
                              data: url, backgroundColor: Colors.white)),
                      const SizedBox(width: 16),
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(url,
                              style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 8),
                          Text(keyboard.hasPairing
                              ? '可收藏手机页面，请勿分享网址。断开全部保留配对；取消配对让旧网址失效。'
                              : '返回后连接继续；闲置 10 分钟或应用进入后台自动断开。'),
                        ],
                      )),
                    ]),
                    SwitchListTile(
                      title: const Text('允许已连接手机读取当前普通输入框文本'),
                      subtitle: const Text(
                          '仅本次连接；可能包含 URL 和其中的私人信息。密码与令牌不回读；支持的凭据输入框只能接收新内容。断开后自动关闭。'),
                      value: keyboard.readTextAllowed,
                      onChanged: keyboard.setReadTextAllowed,
                    ),
                  ] else if (keyboard.error != null)
                    Text(keyboard.error!),
                  if (keyboard.starting) const CircularProgressIndicator(),
                ])),
            actions: [
              TextButton(
                  autofocus: true,
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('返回电视')),
              if (url == null)
                FilledButton(
                    onPressed: keyboard.starting
                        ? null
                        : () {
                            _waitingForConnection = true;
                            if (keyboard.hasPairing) {
                              keyboard.restore(resume: true);
                            } else {
                              keyboard.start(remember: _remember);
                            }
                          },
                    child: Text(keyboard.hasPairing
                        ? '恢复连接'
                        : _remember
                            ? '开启 7 天配对'
                            : '开启临时连接')),
              if (url != null)
                FilledButton(
                    onPressed: keyboard.starting
                        ? null
                        : () {
                            _waitingForConnection = false;
                            if (keyboard.hasPairing) {
                              keyboard.pause();
                            } else {
                              keyboard.disconnect();
                            }
                          },
                    child: Text(count > 0
                        ? '断开全部（$count）'
                        : keyboard.hasPairing
                            ? '暂停遥控'
                            : '关闭连接入口')),
              if (keyboard.hasPairing)
                TextButton(
                    onPressed: keyboard.starting
                        ? null
                        : () {
                            _waitingForConnection = false;
                            keyboard.disconnect();
                          },
                    child: const Text('取消配对')),
            ]);
      });
}
