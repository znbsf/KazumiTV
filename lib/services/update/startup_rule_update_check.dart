import 'package:kazumi/bean/dialog/dialog_helper.dart';

/// Startup rule check, separated from storage and networking for controlled QA.
Future<void> runStartupRuleUpdateCheck({
  required Future<int> Function() check,
  required void Function() update,
}) async {
  final int count;
  try {
    count = await check();
  } catch (_) {
    return;
  }
  if (count > 0) {
    KazumiDialog.showToast(
      message: '检测到 $count 条规则可以更新',
      showActionButton: true,
      actionLabel: '全部更新',
      onActionPressed: update,
      duration: const Duration(seconds: 5),
    );
  }
}
