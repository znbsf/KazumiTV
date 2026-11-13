import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/download/download_danmaku_cache.dart';

void main() {
  test('progress ticks deduplicate and deletion discards a late network reply',
      () async {
    final cache = DownloadDanmakuCache();
    final reply = Completer<Object?>();
    var requests = 0;
    var writes = 0;
    void start() => cache.start('queued',
        hasCache: () async => false,
        fetch: () {
          requests++;
          return reply.future;
        },
        write: (_) async {
          writes++;
        },
        isCurrent: () => true,
        onError: (e, s) => fail('$e'));
    start();
    start();
    start();
    await Future<void>.delayed(Duration.zero);
    expect(requests, 1);
    await cache.retire('queued');
    reply.complete('late');
    await Future<void>.delayed(Duration.zero);
    expect(writes, 0);
  });
  test('retirement waits for a started write before directory reuse', () async {
    final cache = DownloadDanmakuCache();
    final writing = Completer<void>();
    final finish = Completer<void>();
    cache.start('a',
        hasCache: () async => false,
        fetch: () async => 'data',
        write: (_) async {
          writing.complete();
          await finish.future;
        },
        isCurrent: () => true,
        onError: (e, s) => fail('$e'));
    await writing.future;
    var retired = false;
    final retirement = cache.retire('a').then((_) {
      retired = true;
    });
    var retiredAgain = false;
    final secondRetirement = cache.retire('a').then((_) {
      retiredAgain = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(retired, false);
    expect(retiredAgain, false);
    finish.complete();
    await Future.wait([retirement, secondRetirement]);
    expect(retired, true);
    expect(retiredAgain, true);
  });
  test(
      'cached and invalidated tasks never fetch; failures retry only explicitly',
      () async {
    final cache = DownloadDanmakuCache();
    var calls = 0;
    var errors = 0;
    void start(String key, bool exists, bool current) => cache.start(key,
        hasCache: () async => exists,
        fetch: () async {
          calls++;
          throw StateError('429 synthetic');
        },
        write: (_) async => fail('no writes'),
        isCurrent: () => current,
        onError: (e, s) {
          errors++;
        });
    start('cached', true, true);
    start('private', false, false);
    start('failed', false, true);
    await Future<void>.delayed(Duration.zero);
    start('failed', false, true);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(errors, 1);
    await cache.reset('failed');
    start('failed', false, true);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 2);
  });
}
