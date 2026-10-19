import 'dart:convert';
import 'dart:io';

import 'package:kazumi/plugins/rule_overlay.dart';

/// Offline: consumes an app-exported base rule and a small overrides object.
Future<void> main(List<String> args) async {
  if (args.length != 4) {
    stderr.writeln('Usage: dart --packages=.dart_tool/package_config.json '
        'tools/rules/create_overlay.dart base.json overrides.json '
        'upstream-commit output.json');
    exitCode = 64;
    return;
  }
  try {
    final output = File(args[3]);
    if (await output.exists()) {
      throw const FormatException('输出文件已存在；不会覆盖');
    }
    var base = jsonDecode(await File(args[0]).readAsString());
    if (base is List && base.length == 1) base = base.single;
    if (base is! Map) throw const FormatException('请导出一条基础规则');
    final rawOverrides = jsonDecode(await File(args[1]).readAsString());
    if (rawOverrides is! Map) throw const FormatException('覆盖内容需要 JSON 对象');
    final overlay = RuleOverlay.create(
      repository: 'Predidit/KazumiRules',
      commit: args[2],
      baseRule: Map<String, dynamic>.from(base),
      overrides: Map<String, dynamic>.from(rawOverrides),
    );
    final contents =
        const JsonEncoder.withIndent('  ').convert(overlay.toJson());
    await output.writeAsString('$contents\n', flush: true);
    stdout.writeln('已生成本地覆盖文件；尚未导入或部署。');
  } on Object catch (error) {
    stderr.writeln('无法生成覆盖文件：$error');
    exitCode = 1;
  }
}
