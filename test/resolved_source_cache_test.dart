import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/video_source/resolved_source_cache.dart';
import 'package:kazumi/services/video_source/video_source_format.dart';
import 'package:kazumi/services/video_source/video_source_service.dart';

void main() {
  late DateTime now;
  late ResolvedSourceCache cache;
  const source = VideoSource(
    url: 'https://media.test/movie.m3u8?sign=exact%2Bbytes',
    offset: 40,
    type: VideoSourceType.online,
    format: VideoSourceFormat.hls,
  );
  ResolvedSourceAttempt confirmed() => ResolvedSourceAttempt(
      source, {'referer': 'https://source.test/', 'user-agent': 'original-ua'},
      fromCache: false);
  Future<void> seed(String key) => cache.rememberAfterFirstFrame(
      key: key,
      attempt: confirmed(),
      firstFrame: Future.value(),
      isCurrent: () => true);
  Future<ResolvedSourceAttempt> fail(String key,
          {Object error =
              const VideoSourceTimeoutException(Duration(seconds: 15)),
          bool current = true}) =>
      cache.resolve(
        key: key,
        offset: 99,
        headers: {'user-agent': 'new-ua'},
        fresh: () => Future.error(error),
        isCurrent: () => current,
      );

  setUp(() {
    now = DateTime.utc(2026, 10, 19);
    cache = ResolvedSourceCache(now: () => now, capacity: 2);
  });

  test('confirmed same episode falls back once with exact URL and old headers',
      () async {
    await seed('source-A/road-1/episode-2');
    final result = await fail('source-A/road-1/episode-2');
    expect(result.fromCache, isTrue);
    expect(result.source.url, source.url);
    expect(result.source.offset, 99);
    expect(result.source.format, VideoSourceFormat.hls);
    expect(result.headers['user-agent'], 'original-ua');
    await expectLater(fail('source-A/road-1/episode-2'),
        throwsA(isA<VideoSourceTimeoutException>()));
  });

  test('never uses episode 2 for episode 3 or another source or road',
      () async {
    await seed('A/1/2');
    for (final key in ['A/1/3', 'B/1/2', 'A/2/2']) {
      await expectLater(fail(key), throwsA(isA<VideoSourceTimeoutException>()));
    }
    expect((await fail('A/1/2')).fromCache, isTrue);
  });

  test('fresh result wins and resolving alone never populates cache', () async {
    await seed('old');
    final result = await cache.resolve(
        key: 'new',
        offset: 3,
        headers: {},
        fresh: () async => source,
        isCurrent: () => true);
    expect(result.fromCache, isFalse);
    await expectLater(fail('new'), throwsA(isA<VideoSourceTimeoutException>()));
  });

  test('expiry at five minutes and clock rollback both reject entries',
      () async {
    await seed('expired');
    now = now.add(const Duration(minutes: 5));
    await expectLater(
        fail('expired'), throwsA(isA<VideoSourceTimeoutException>()));
    await seed('rollback');
    now = now.subtract(const Duration(seconds: 1));
    await expectLater(
        fail('rollback'), throwsA(isA<VideoSourceTimeoutException>()));
  });

  test('cancelled, superseded and unexpected errors never use cached address',
      () async {
    await seed('same');
    await expectLater(
        fail('same', error: const VideoSourceCancelledException()),
        throwsA(isA<VideoSourceCancelledException>()));
    await expectLater(fail('same', current: false),
        throwsA(isA<VideoSourceTimeoutException>()));
    await expectLater(fail('same', error: StateError('bug')), throwsStateError);
    expect((await fail('same')).fromCache, isTrue);
  });

  test('delayed first frame after leaving the episode cannot confirm',
      () async {
    final frame = Completer<void>();
    var current = true;
    final pending = cache.rememberAfterFirstFrame(
        key: 'same',
        attempt: confirmed(),
        firstFrame: frame.future,
        isCurrent: () => current);
    current = false;
    frame.complete();
    await pending;
    await expectLater(
        fail('same'), throwsA(isA<VideoSourceTimeoutException>()));
  });

  test('first frame failure is not cached', () async {
    await cache.rememberAfterFirstFrame(
        key: 'same',
        attempt: confirmed(),
        firstFrame: Future.error(StateError('output failed')),
        isCurrent: () => true);
    await expectLater(
        fail('same'), throwsA(isA<VideoSourceTimeoutException>()));
  });

  test('fallback first frame cannot renew or replenish a consumed address',
      () async {
    await seed('same');
    final fallback =
        await fail('same', error: const VideoSourceNotFoundException());
    await cache.rememberAfterFirstFrame(
        key: 'same',
        attempt: fallback,
        firstFrame: Future.value(),
        isCurrent: () => true);
    await expectLater(
        fail('same'), throwsA(isA<VideoSourceTimeoutException>()));
  });

  test('bounded cache evicts oldest and native failure invalidates', () async {
    await seed('one');
    await seed('two');
    await seed('three');
    await expectLater(fail('one'), throwsA(isA<VideoSourceTimeoutException>()));
    cache.invalidate('two');
    await expectLater(fail('two'), throwsA(isA<VideoSourceTimeoutException>()));
    expect((await fail('three')).fromCache, isTrue);
  });
}
