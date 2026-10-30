import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/logging/bounded_log_file.dart';
import 'package:kazumi/pages/player/controller/player_debug_controller.dart';

void main() {
  test('player memory logs stay bounded after clear and oversized messages',
      () {
    final controller = PlayerDebugController();
    for (var i = 0; i < 10000; i++) {
      controller.appendLog('$i ${'字' * 5000}');
    }
    expect(controller.playerLog.length, lessThanOrEqualTo(500));
    expect(controller.playerLog.fold<int>(0, (n, s) => n + s.length),
        lessThanOrEqualTo(256 * 1024));
    expect(controller.playerLog.last, startsWith('9999'));
    controller.playerLog.clear();
    controller.appendLog('decoder failure');
    expect(controller.playerLog, ['decoder failure']);
  });

  test(
      'rotation and bounded UTF8 tail retain latest records and clear archives',
      () async {
    final dir = await Directory.systemTemp.createTemp('kazumi_log_test_');
    try {
      final file = File('${dir.path}/log');
      final log = BoundedLogFile(file, maxBytes: 128);
      for (var i = 0; i < 100; i++) {
        await log.append('line $i 中文🙂\n');
      }
      for (final entry in await dir.list().toList()) {
        expect(await File(entry.path).length(), lessThanOrEqualTo(128));
      }
      expect((await dir.list().toList()).length, 3);
      final tail = await log.tail(maxBytes: 70);
      expect(tail, contains('line 99 中文🙂'));
      expect(tail, isNot(contains('�')));
      expect(tail, contains('较早内容已省略'));
      await log.clear();
      expect(await log.tail(), '');
      expect((await dir.list().toList()).length, 1);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
