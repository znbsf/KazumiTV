import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/webview/video/legacy_parser_scripts.dart';

void main() {
  test(
      'shared production parser scripts execute across navigation and hook lifetimes',
      () async {
    final process = await Process.start(
        'node', ['test_support/legacy_webview_script_harness.cjs']);
    process.stdin.write(jsonEncode({
      'normal1': legacyVideoParserScript(session: 1, iframeOnly: false),
      'normal2': legacyVideoParserScript(session: 2, iframeOnly: false),
      'iframe1': legacyVideoParserScript(session: 1, iframeOnly: true),
      'poll1': legacyVideoParserPollScript(1),
    }));
    await process.stdin.close();
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    final code = await process.exitCode.timeout(const Duration(seconds: 15),
        onTimeout: () {
      process.kill();
      throw TimeoutException('Production script harness did not finish.');
    });
    expect(code, 0, reason: await errors);
    final report = jsonDecode(await output) as Map<String, dynamic>;
    final checks = report['checks'] as List<dynamic>;
    expect(checks, hasLength(10));
    expect(checks.every((check) => check['passed'] == true), isTrue);
  });
}
