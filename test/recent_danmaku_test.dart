import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'package:kazumi/services/player/recent_danmaku.dart';

DanmakuLoadResult comments(String text) => DanmakuLoadResult.success(danmakus: [
      DanmakuEntry(
          message: text,
          time: 1,
          type: 1,
          color: Colors.white,
          source: '[Test]')
    ], bangumiID: 1);

void main() {
  test('fresh comments win and update cache without reading old comments',
      () async {
    var reads = 0;
    DanmakuLoadResult? saved;
    final result = await loadRecentDanmaku(
        fresh: () async => comments('new'),
        cached: () async {
          reads++;
          return comments('old');
        },
        save: (v) async {
          saved = v;
        },
        isCurrent: () => true,
        deduplicate: false);
    expect(result.$1.danmakus.single.message, 'new');
    expect(result.$2, false);
    expect(saved!.danmakus.single.message, 'new');
    expect(reads, 0);
  });
  for (final empty in [true, false]) {
    test(
        '${empty ? 'empty' : 'failed'} online result falls back, preserving cache',
        () async {
      var writes = 0;
      final result = await loadRecentDanmaku(
          fresh: () async => empty
              ? DanmakuLoadResult.success(danmakus: [], bangumiID: 1)
              : DanmakuLoadResult.failed(bangumiID: 1),
          cached: () async => comments('saved'),
          save: (_) async {
            writes++;
          },
          isCurrent: () => true,
          deduplicate: false);
      expect(result.$2, true);
      expect(result.$1.prepared![1]!.single.message, 'saved');
      expect(writes, 0);
    });
  }
  test('late completion after episode switch cannot read or overwrite cache',
      () async {
    var current = true;
    var touches = 0;
    final network = Completer<DanmakuLoadResult>();
    final pending = loadRecentDanmaku(
        fresh: () => network.future,
        cached: () async {
          touches++;
          return comments('old');
        },
        save: (_) async {
          touches++;
        },
        isCurrent: () => current,
        deduplicate: false);
    final assertion =
        expectLater(pending, throwsA(isA<DanmakuLoadCancelled>()));
    current = false;
    network.complete(comments('new'));
    await assertion;
    expect(touches, 0);
  });
  test('cancelled network must not fall back to cached comments', () async {
    var reads = 0;
    await expectLater(
        loadRecentDanmaku(
            fresh: () async => throw const DanmakuLoadCancelled(),
            cached: () async {
              reads++;
              return comments('old');
            },
            save: (_) async {},
            isCurrent: () => true,
            deduplicate: false),
        throwsA(isA<DanmakuLoadCancelled>()));
    expect(reads, 0);
  });
  test('cache write error does not discard fresh comments', () async {
    final result = await loadRecentDanmaku(
        fresh: () async => comments('new'),
        cached: () async => comments('old'),
        save: (_) async => throw StateError('disk'),
        isCurrent: () => true,
        deduplicate: false);
    expect(result.$1.danmakus.single.message, 'new');
    expect(result.$2, false);
  });
}
