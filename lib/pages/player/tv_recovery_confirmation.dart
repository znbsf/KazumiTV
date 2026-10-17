import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TvRecoveryConfirmation extends StatelessWidget {
  const TvRecoveryConfirmation(
      {super.key, required this.onCancel, required this.onConfirm});
  final VoidCallback onCancel, onConfirm;

  @override
  Widget build(BuildContext context) => Focus(
        skipTraversal: true,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              [
                LogicalKeyboardKey.escape,
                LogicalKeyboardKey.goBack,
                LogicalKeyboardKey.browserBack
              ].contains(event.logicalKey)) {
            onCancel();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AlertDialog(
          title: const Text('尝试软件兼容播放？'),
          content: const Text(
              '硬件解码路径报告错误，可能与当前视频源兼容性有关。确认后将重新打开本集并恢复播放位置、暂停状态、倍速及音轨/字幕选择。软件解码可能卡顿；仅尝试一次，不修改默认设置。'),
          actions: [
            TextButton(
                autofocus: true, onPressed: onCancel, child: const Text('取消')),
            TextButton(onPressed: onConfirm, child: const Text('尝试软件解码')),
          ],
        ),
      );
}
