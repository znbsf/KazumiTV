import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/utils/danmaku.dart';

List<DanmakuEntry> fixture(int count) => List.generate(
    count,
    (i) => DanmakuEntry(
        message: ' Ｔｅｓｔ 中文 ${i % 7000} !!! ',
        time: i / 20,
        type: 1,
        color: Colors.white,
        source: 'synthetic'));

void main() {
  test('large preparation yields the UI event loop and preserves exact results',
      () async {
    for (final count in [1000, 10000, 50000]) {
      final data = fixture(count);
      final expected = indexDanmakus((data, true));
      final watch = Stopwatch()..start();
      final event = Completer<int>();
      Timer.run(() => event.complete(watch.elapsedMicroseconds));
      final result = await prepareDanmakus(data, deduplicate: true);
      final elapsed = watch.elapsedMicroseconds;
      final delay = await event.future;
      print(
          'DANMAKU prepared count=$count elapsed_us=$elapsed event_delay_us=$delay');
      expect(result.keys, expected.keys);
      expect(result.values.expand((v) => v).map((e) => e.toJson()).toList(),
          expected.values.expand((v) => v).map((e) => e.toJson()).toList());
    }
  });
  test(
      'measure synchronous normalization and grouping (host, not TV frame time)',
      () async {
    for (final count in [1000, 10000, 50000]) {
      final data = fixture(count);
      final watch = Stopwatch()..start();
      final event = Completer<int>();
      Timer.run(() => event.complete(watch.elapsedMicroseconds));
      final result = mergeDuplicateDanmakus(data, timeWindowSeconds: 5);
      final elapsed = watch.elapsedMicroseconds;
      final blocked = await event.future;
      print(
          'DANMAKU baseline count=$count elapsed_us=$elapsed event_delay_us=$blocked output=${result.length}');
      expect(result, isNotEmpty);
    }
  });
}
