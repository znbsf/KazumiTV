import 'dart:convert';

/// A bounded, already-redacted snapshot. Never a filesystem capability.
class LogExport {
  LogExport({required this.text, required this.createdAt}) {
    if (utf8.encode(text).length > maxBytes) {
      throw ArgumentError('Log export too large');
    }
  }
  static const maxBytes = 512 * 1024;
  final String text;
  final DateTime createdAt;
  String get filename =>
      'kazumitv-log-${createdAt.toUtc().toIso8601String().replaceAll(RegExp(r'[^0-9TZ]'), '')}.txt';
}

String formatLogExport(String raw,
    {required DateTime createdAt,
    required String version,
    required String platform}) {
  final clean = raw.split('\n').map(redactExportLine).join('\n');
  final header = 'KazumiTV 问题反馈日志\n'
      '版本：$version\n平台：$platform\n'
      '导出时间：${createdAt.toIso8601String()} (UTC${createdAt.timeZoneOffset.isNegative ? '' : '+'}${createdAt.timeZoneOffset.inMinutes} 分钟)\n'
      '范围：近期应用日志，不包含系统 logcat。\n'
      '已遮盖常见凭据、地址与账号字段；提交公开 Issue 前仍请检查。\n'
      '请补充出错时间、最后一次操作、复现步骤及预期结果。\n\n';
  final bytes = utf8.encode(clean.isEmpty ? '暂无应用日志。\n' : clean);
  final budget = LogExport.maxBytes - utf8.encode(header).length - 128;
  final body = bytes.length <= budget
      ? clean.isEmpty
          ? '暂无应用日志。\n'
          : clean
      : '${utf8.decode(bytes.sublist(bytes.length - budget), allowMalformed: true)}\n（导出大小受限，较早内容已省略）\n';
  return '$header$body';
}

/// Conservative sharing copy; the original on TV is never changed. No
/// redactor can identify arbitrary prose secrets, so the UI offers a preview.
String redactExportLine(String input) {
  var text = input.replaceAll(r'\/', '/');
  for (var i = 0; i < 2; i++) {
    try {
      final decoded = Uri.decodeFull(text);
      if (decoded == text) break;
      text = decoded;
    } on FormatException {
      break;
    } on ArgumentError {
      break;
    }
  }
  text = text.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');
  text = text.replaceAll(
      RegExp(
          r'''(?:https?|file|content)(?::|%3a|%253a)(?://|%2f%2f|%252f%252f)[^\s<>"']+''',
          caseSensitive: false),
      '[地址已遮盖]');
  text = text.replaceAll(
      RegExp(
          r'''(?:authorization|proxy-authorization|cookie|set-cookie)["']?\s*[:=][^\r\n]*''',
          caseSensitive: false),
      '[认证头已遮盖]');
  text = text.replaceAll(
      RegExp(
          r'''(?:\b(?:[a-z0-9_.-]*(?:token|password|passwd|secret)|sign|signature|(?:api|access|secret)[_-]?key|username|user[_-]?id|account|email|device[_-]?id|android[_-]?id|serial)\b|密码|令牌|账号|账户|用户名)["']?\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^\s,;}\]]+)''',
          caseSensitive: false),
      '[敏感字段已遮盖]');
  text = text.replaceAll(
      RegExp(r'\b(?:Bearer|Basic)\s+\S+', caseSensitive: false), '[凭据已遮盖]');
  text = text.replaceAll(
      RegExp(r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
          caseSensitive: false),
      '[邮箱已遮盖]');
  text = text.replaceAll(RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'), '[IP已遮盖]');
  text = text.replaceAll(
      RegExp(
          r'\b(?:[a-f0-9]{1,4}:){4,}[a-f0-9:]+\b|(?<![a-z0-9])[a-f0-9]*::[a-f0-9:]+\b',
          caseSensitive: false),
      '[地址已遮盖]');
  text = text.replaceAll(
      RegExp(
          r'''(?:[A-Z]:[\\/]|\\\\[^\s\\]+\\|/(?:data|sdcard|storage|home|Users|mnt|private|var)/)[^\s"'<>]+''',
          caseSensitive: false),
      '[本地路径已遮盖]');
  text = text.replaceAll(
      RegExp(r'\b[a-f0-9]{32,}\b|\b[A-Za-z0-9_+/=-]{48,}\b',
          caseSensitive: false),
      '[标识已遮盖]');
  return text.replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'), '');
}
