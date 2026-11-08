import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/danmaku/danmaku_cache_service.dart';
import 'package:kazumi/services/danmaku/danmaku_cache_store.dart';

Map<String, dynamic> comments(String text) => {
      'comments': [
        {'p': '1,1,16777215,[test]', 'm': text}
      ],
    };
final episode = Uri.parse('https://api.dandanplay.net/api/v2/comment/123');

void main() {
  test('expired empty comments cannot hide a service rate limit', () async {
    final root = await Directory.systemTemp.createTemp('kazumi_empty_cache_');
    var now = DateTime.now();
    final cache = DanmakuCacheService(
        directory: () async => root,
        enabled: () => true,
        privateMode: () => false,
        limitMiB: () => 256,
        clock: () => now);
    try {
      await cache.get(episode, () async => {'comments': []});
      now = now.add(const Duration(minutes: 11));
      const error = NetworkException(
          type: NetworkExceptionType.badResponse,
          statusCode: 429,
          message: 'limited');
      await expectLater(
          cache.get(episode, () async => throw error), throwsA(same(error)));
    } finally {
      await cache.close();
      expect(root.absolute.path.startsWith(Directory.systemTemp.absolute.path),
          isTrue);
      expect(root.uri.pathSegments.where((s) => s.isNotEmpty).last,
          startsWith('kazumi_empty_cache_'));
      await root.delete(recursive: true);
    }
  });
  test('airing episode lists refresh sooner than stable ID mappings', () {
    expect(
        DanmakuCachePolicy.forUri(
                Uri.parse('https://api.dandanplay.net/api/v2/bangumi/1'))!
            .freshFor,
        const Duration(hours: 6));
  });
  late Directory root;
  late DateTime now;
  late DanmakuCacheStore store;
  late DanmakuCacheService service;
  var enabled = true;
  var privateMode = false;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('kazumi_danmaku_cache_');
    now = DateTime.now();
    enabled = true;
    privateMode = false;
    store = DanmakuCacheStore(root, clock: () => now);
    service = DanmakuCacheService(
        directory: () async => root,
        enabled: () => enabled,
        privateMode: () => privateMode,
        limitMiB: () => 256,
        clock: () => now);
  });
  tearDown(() async {
    await service.close();
    expect(root.absolute.path.startsWith(Directory.systemTemp.absolute.path),
        isTrue);
    expect(root.uri.pathSegments.where((s) => s.isNotEmpty).last,
        startsWith('kazumi_danmaku_cache_'));
    await root.delete(recursive: true);
  });

  test('only public read endpoints are cacheable, query order is canonical',
      () {
    expect(
        DanmakuCachePolicy.forUri(episode)!.freshFor, const Duration(hours: 6));
    expect(
        DanmakuCachePolicy.forUri(
                Uri.parse('https://api.dandanplay.net/api/v2/bangumi/bgmtv/1'))!
            .freshFor,
        const Duration(days: 7));
    for (final url in [
      'http://api.dandanplay.net/api/v2/comment/123',
      'https://other.test/api/v2/comment/123',
      'https://api.dandanplay.net/api/v2/comment/123/app',
      'https://api.dandanplay.net/api/v2/login'
    ]) {
      expect(DanmakuCachePolicy.forUri(Uri.parse(url)), isNull);
    }
    expect(DanmakuCachePolicy.keyFor(episode.replace(query: 'b=2&a=1')),
        DanmakuCachePolicy.keyFor(episode.replace(query: 'a=1&b=2')));
    expect(
        DanmakuCachePolicy.keyFor(episode.replace(query: 'chConvert=0')),
        isNot(
            DanmakuCachePolicy.keyFor(episode.replace(query: 'chConvert=2'))));
  });

  test('a second load and a restarted worker need no network call', () async {
    var calls = 0;
    Future<dynamic> fresh() async {
      calls++;
      return comments('saved');
    }

    expect((await service.get(episode, fresh))['comments'], isNotEmpty);
    await service.get(episode, fresh);
    await service.close();
    await service.get(episode, fresh);
    expect(calls, 1);
    expect((await service.stats())['entries'], 1);
  });

  test('concurrent loads of an episode share a single network request',
      () async {
    var calls = 0;
    Future<dynamic> fresh() async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return comments('one');
    }

    final values = await Future.wait(
        List.generate(12, (_) => service.get(episode, fresh)));
    expect(calls, 1);
    expect(values, hasLength(12));
  });

  test('comments, mapping and search keep independent valid lifetimes',
      () async {
    var calls = 0;
    final mapping =
        Uri.parse('https://api.dandanplay.net/api/v2/bangumi/bgmtv/99');
    final search = Uri.parse(
        'https://api.dandanplay.net/api/v2/search/episodes?anime=title&v2=true');
    Future<dynamic> freshComments() async {
      calls++;
      return comments('latest');
    }

    Future<dynamic> freshMapping() async {
      calls++;
      return {
        'bangumi': {'animeId': 5, 'episodes': []},
        'success': true,
        'errorCode': 0
      };
    }

    Future<dynamic> freshSearch() async {
      calls++;
      return {
        'animes': [
          {'animeId': 5}
        ]
      };
    }

    await service.get(episode, freshComments);
    await service.get(mapping, freshMapping);
    await service.get(search, freshSearch);
    now = now.add(const Duration(hours: 7));
    await service.get(episode, freshComments);
    await service.get(mapping, freshMapping);
    await service.get(search, freshSearch);
    expect(calls, 5); // Both six-hour entries renew; mapping stays local.
  });

  test(
      'expired data survives 429 and cooldown also prevents different requests',
      () async {
    await service.get(episode, () async => comments('old'));
    now = now.add(const Duration(hours: 7));
    var calls = 0;
    final raw = DioException(
        requestOptions: RequestOptions(path: episode.path),
        response: Response(
            requestOptions: RequestOptions(path: episode.path),
            statusCode: 429,
            headers: Headers.fromMap({
              'retry-after': ['3600']
            })));
    final failure = NetworkException(
        type: NetworkExceptionType.badResponse,
        statusCode: 429,
        message: 'limited',
        rawError: raw);
    Future<dynamic> limited() async {
      calls++;
      throw failure;
    }

    final result = await service.get(episode, limited);
    expect(result, comments('old'));
    await service.get(episode, limited);
    final other = episode.replace(path: '/api/v2/comment/456');
    await expectLater(service.get(other, limited), throwsA(same(failure)));
    now = now.add(const Duration(minutes: 30));
    await expectLater(service.get(other, limited), throwsA(same(failure)));
    expect(calls, 1);
    now = now.add(const Duration(minutes: 31));
    await service.get(other, () async {
      calls++;
      return comments('restored');
    });
    expect(calls, 2);
  });

  test('empty and failed refreshes preserve useful stale comments', () async {
    await service.get(episode, () async => comments('old'));
    now = now.add(const Duration(hours: 7));
    expect(await service.get(episode, () async => {'comments': []}),
        comments('old'));
    expect(
        await service.get(
            episode, () async => throw const SocketException('offline')),
        comments('old'));
  });

  test('authentication errors and cancellation do not fall back', () async {
    await service.get(episode, () async => comments('old'));
    now = now.add(const Duration(hours: 7));
    for (final error in [
      const NetworkException(
          type: NetworkExceptionType.cancel, message: 'cancel'),
      const NetworkException(
          type: NetworkExceptionType.badResponse,
          statusCode: 403,
          message: 'forbidden'),
    ]) {
      await expectLater(
          service.get(episode, () async => throw error), throwsA(same(error)));
    }
  });

  test('disabled and private requests neither reuse nor replace saved data',
      () async {
    await service.get(episode, () async => comments('saved'));
    privateMode = true;
    expect(await service.get(episode, () async => comments('private')),
        comments('private'));
    privateMode = false;
    enabled = false;
    expect(await service.get(episode, () async => comments('disabled')),
        comments('disabled'));
    enabled = true;
    expect(
        await service.get(
            episode, () async => throw StateError('must not fetch')),
        comments('saved'));
  });

  test('clearing during a pending fetch cannot repopulate the cache', () async {
    final started = Completer<void>();
    final network = Completer<dynamic>();
    final pending = service.get(episode, () {
      started.complete();
      return network.future;
    });
    await started.future;
    await service.clear();
    network.complete(comments('late'));
    await pending;
    expect((await service.stats())['entries'], 0);
  });

  test('API errors and unknown bodies never become successful cache entries',
      () async {
    var calls = 0;
    for (final value in [
      {'success': false, 'errorCode': 1},
      'bad',
      {'comments': 'bad'}
    ]) {
      for (var repeat = 0; repeat < 2; repeat++) {
        expect(
            await service.get(episode, () async {
              calls++;
              return value;
            }),
            value);
      }
    }
    expect(calls, 6);
    expect((await service.stats())['entries'], 0);
  });

  test('empty results expire sooner, stale files expire after thirty days',
      () async {
    final key = DanmakuCachePolicy.keyFor(episode);
    await store.write(key, {'comments': []}, empty: true);
    now = now.add(const Duration(minutes: 11));
    expect((await store.read(key, const Duration(hours: 6)))!['fresh'], false);
    now = now.add(const Duration(days: 31));
    expect(await store.read(key, const Duration(hours: 6)), isNull);
    expect((await store.stats())['entries'], 0);
  });

  test('LRU eviction respects bytes and reads protect the recently used entry',
      () async {
    final random = Random(7);
    Map<String, dynamic> data() => comments(
        base64.encode(List.generate(2000, (_) => random.nextInt(256))));
    final keys = List.generate(
        3,
        (i) => DanmakuCachePolicy.keyFor(
            episode.replace(path: '/api/v2/comment/$i')));
    await store.write(keys[0], data(), empty: false);
    now = now.add(const Duration(seconds: 1));
    await store.write(keys[1], data(), empty: false);
    store.limitBytes = (await store.stats())['bytes']!;
    now = now.add(const Duration(seconds: 1));
    await store.read(keys[0], const Duration(hours: 6));
    now = now.add(const Duration(seconds: 1));
    await store.write(keys[2], data(), empty: false);
    expect(await store.read(keys[1], const Duration(hours: 6)), isNull);
    expect(await store.read(keys[0], const Duration(hours: 6)), isNotNull);
    expect((await store.stats())['bytes'], lessThanOrEqualTo(store.limitBytes));
  });

  test('corrupt files are discarded and clearing touches only owned entries',
      () async {
    final key = DanmakuCachePolicy.keyFor(episode);
    await store.write(key, comments('one'), empty: false);
    await File('${root.path}/$key.json.gz').writeAsString('broken gzip');
    expect(await store.read(key, const Duration(hours: 6)), isNull);
    final sentinel = File('${root.path}/unrelated.txt');
    await sentinel.writeAsString('preserve');
    await store.clear();
    expect(await sentinel.readAsString(), 'preserve');
    expect(await store.read('../escape', const Duration(hours: 6)), isNull);
  });
}
