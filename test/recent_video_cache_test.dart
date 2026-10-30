import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/recent_video_cache.dart';

void main() {
  late Directory directory;
  late HttpServer origin;
  late HttpClient client;
  late RecentVideoCache cache;
  late String source;
  late Map<String, int> requests;
  late int free;
  late String playlist;
  late Future<void> Function(HttpRequest)? handler;
  const body = [10, 20, 30, 40, 50];
  const manifest = '#EXTM3U\n#EXT-X-TARGETDURATION:5\n'
      '#EXTINF:5,\na.ts\n#EXTINF:5,\nb.ts\n#EXT-X-ENDLIST\n';

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('recent_cache_test_');
    free = 20 * 1024 * 1024 * 1024;
    cache = RecentVideoCache(Directory('${directory.path}/cache'),
        availableBytes: (_) async => free);
    origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = HttpClient();
    source = 'http://127.0.0.1:${origin.port}/show/list.m3u8';
    requests = {};
    playlist = manifest;
    handler = null;
    origin.listen((request) async {
      final path = request.uri.path;
      requests.update(path, (v) => v + 1, ifAbsent: () => 1);
      try {
        if (handler != null) {
          await handler!(request);
        } else if (path.endsWith('.m3u8')) {
          request.response.write(playlist);
        } else {
          request.response.contentLength = body.length;
          if (request.headers.value('range') == 'bytes=0-') {
            request.response.statusCode = 206;
            request.response.headers.set('Content-Range', 'bytes 0-4/5');
          }
          request.response.add(body);
        }
        await request.response.close();
      } catch (_) {}
    });
  });
  tearDown(() async {
    await cache.close();
    client.close(force: true);
    await origin.close(force: true);
    await directory.delete(recursive: true);
  });

  Future<Map<String, dynamic>?> open([String identity = 'episode-1']) =>
      cache.openOnline(
          identity: identity,
          url: source,
          headers: const {},
          metadata: const {'title': 'Test', 'episode': 1});
  Future<(int, List<int>)> get(String url, {String? range}) async {
    final request = await client.getUrl(Uri.parse(url));
    if (range != null) request.headers.set('Range', range);
    final response = await request.close();
    final bytes = await response.fold<List<int>>([], (a, b) => a..addAll(b));
    return (response.statusCode, bytes);
  }

  String segment(Map lease, int index) =>
      (lease['url'] as String).replaceFirst('playlist.m3u8', 's$index.ts');
  Future<void> consume(Map lease) async {
    expect((await get(segment(lease, 0))).$2, body);
    expect((await get(segment(lease, 1))).$2, body);
  }

  test('one download per segment, survives restart, offline never needs origin',
      () async {
    final lease = (await open())!;
    final localManifest = utf8.decode((await get(lease['url'])).$2);
    expect(localManifest, contains('s0.ts'));
    expect(localManifest, isNot(contains('http')));
    await consume(lease);
    await get(segment(lease, 0));
    expect(requests, {'/show/list.m3u8': 1, '/show/a.ts': 1, '/show/b.ts': 1});
    await cache.release(lease['token']);
    await origin.close(force: true);
    cache = RecentVideoCache(Directory('${directory.path}/cache'),
        availableBytes: (_) async => free);
    final local = (await cache.openOffline(lease['id']))!;
    expect(local['complete'], true);
    expect(local['offline'], true);
    await consume(local);
    final bounded = await get(segment(local, 0), range: 'bytes=1-3');
    expect(bounded.$1, 206);
    expect(bounded.$2, [20, 30, 40]);
    final suffix = await get(segment(local, 0), range: 'bytes=-2');
    expect(suffix.$1, 206);
    expect(suffix.$2, [40, 50]);
    expect((await get(segment(local, 0), range: 'bytes=99-')).$1, 416);
    await cache.release(local['token']);
  });

  test(
      'FFmpeg full Range response is cacheable; concurrent requests share bytes',
      () async {
    final lease = (await open())!;
    final responses = await Future.wait([
      get(segment(lease, 0), range: 'bytes=0-'),
      get(segment(lease, 0), range: 'bytes=0-'),
    ]);
    expect(responses.every((r) => r.$1 == 206 && r.$2.length == 5), true);
    expect(requests['/show/a.ts'], 1);
    expect((await cache.list()).single['saved'], 1);
    expect(await cache.openOffline(lease['id']), isNull);
  });

  test('partial cache restarts and changed manifest invalidates saved segments',
      () async {
    final first = (await open())!;
    await get(segment(first, 0));
    await cache.release(first['token']);
    playlist = manifest.replaceAll('a.ts', 'changed.ts');
    final second = (await open())!;
    expect(second['saved'], 0);
    await get(segment(second, 0));
    expect(requests['/show/changed.ts'], 1);
    expect((await cache.list()).single['complete'], false);
  });

  test('LRU quota protects active entries and manual download siblings',
      () async {
    final manual = File('${directory.path}/manual.mp4');
    await manual.writeAsString('manual');
    await cache.configure(RecentVideoCache.entryOverhead * 2 + 20);
    final a = (await open('a'))!;
    await consume(a);
    final b = (await open('b'))!;
    await consume(b);
    expect(await open('c'), isNull); // both entries leased
    await cache.release(a['token']);
    final c = (await open('c'))!;
    expect(await cache.openOffline(a['id']), isNull);
    expect((await cache.list()).map((e) => e['id']), contains(b['id']));
    await cache.clear(id: b['id']); // leased entry cannot be deleted
    expect((await cache.list()).length, 2);
    await cache.release(b['token']);
    await cache.clear(id: b['id']);
    expect((await cache.list()).single['id'], c['id']);
    expect(await manual.readAsString(), 'manual');
  });

  test(
      'low storage bypasses preparation and later stops writes without losing playback',
      () async {
    free = RecentVideoCache.reserveBytes - 1;
    expect(await open(), isNull);
    free = RecentVideoCache.reserveBytes + 100;
    final lease = (await open())!;
    free = 0;
    await consume(lease);
    expect((await cache.list()).single['saved'], 0);
  });

  test('quota exhausted within current episode still relays all bytes',
      () async {
    await cache.configure(RecentVideoCache.entryOverhead + 6);
    final lease = (await open())!;
    await consume(lease);
    final state = (await cache.list()).single;
    expect(state['saved'], 1);
    expect(
        state['bytes'], lessThanOrEqualTo(RecentVideoCache.entryOverhead + 6));
    expect(await cache.openOffline(lease['id']), isNull);
  });

  test('truncated content is never promoted to complete', () async {
    handler = (request) async {
      if (request.uri.path.endsWith('.m3u8')) {
        request.response.write(manifest);
      } else {
        request.response.contentLength = 100;
        request.response.add(body);
        final socket = await request.response.detachSocket(writeHeaders: true);
        socket.destroy();
      }
    };
    final lease = (await open())!;
    try {
      await get(segment(lease, 0));
    } catch (_) {}
    await cache.release(lease['token']);
    expect((await cache.list()).single['saved'], 0);
    expect(
        await Directory('${directory.path}/cache/${lease['id']}')
            .list()
            .any((f) => f.path.endsWith('.part')),
        false);
  });

  test('releasing mid-stream aborts work and removes partial files', () async {
    final started = Completer<void>();
    final finish = Completer<void>();
    handler = (request) async {
      if (request.uri.path.endsWith('.m3u8')) {
        request.response.write(manifest);
      } else {
        request.response.contentLength = 100;
        request.response.add(body);
        await request.response.flush();
        if (!started.isCompleted) started.complete();
        await finish.future;
      }
    };
    final lease = (await open())!;
    final pending = get(segment(lease, 0)).then<void>((_) {}, onError: (_) {});
    await started.future;
    await cache.release(lease['token']).timeout(const Duration(seconds: 3));
    finish.complete();
    await pending;
    expect((await cache.list()).single['saved'], 0);
  });

  test('missing cached file is reclassified as partial after restart',
      () async {
    final lease = (await open())!;
    await consume(lease);
    await cache.release(lease['token']);
    await File('${directory.path}/cache/${lease['id']}/s0.ts').delete();
    cache = RecentVideoCache(Directory('${directory.path}/cache'),
        availableBytes: (_) async => free);
    expect(await cache.openOffline(lease['id']), isNull);
    expect((await cache.list()).single['saved'], 1);
  });

  test('danmaku persists and a single-episode deletion removes both', () async {
    final lease = (await open())!;
    await consume(lease);
    await cache.saveDanmaku(lease['id'], '{"entries":["latest"]}');
    expect(await cache.readDanmaku(lease['id']), contains('latest'));
    await cache.release(lease['token']);
    cache = RecentVideoCache(Directory('${directory.path}/cache'),
        availableBytes: (_) async => free);
    expect(await cache.readDanmaku(lease['id']), contains('latest'));
    await cache.clear(id: lease['id']);
    expect(await cache.readDanmaku(lease['id']), isNull);
    expect(await cache.list(), isEmpty);
  });

  for (final (name, content) in [
    ('nested media segment', manifest.replaceAll('a.ts', 'a.m3u8')),
    ('live', manifest.replaceAll('#EXT-X-ENDLIST', '')),
    (
      'encrypted',
      manifest.replaceAll(
          '#EXTINF:5,', '#EXT-X-KEY:METHOD=AES-128,URI="key"\n#EXTINF:5,')
    ),
    (
      'byte range',
      manifest.replaceAll('#EXTINF:5,', '#EXT-X-BYTERANGE:5@0\n#EXTINF:5,')
    ),
    ('external tracks', '#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,URI="audio.m3u8"\n'),
    (
      'multiple variants',
      '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=100\na\n#EXT-X-STREAM-INF:BANDWIDTH=200\nb\n'
    ),
  ]) {
    test('unsupported $name leaves normal playback path available', () async {
      playlist = content;
      expect(await open(), isNull);
      expect(await cache.list(), isEmpty);
    });
  }

  test(
      'bounded streaming transfers a large segment without whole-file buffering',
      () async {
    const size = 16 * 1024 * 1024;
    final chunk = Uint8List(65536);
    handler = (request) async {
      if (request.uri.path.endsWith('.m3u8')) {
        request.response.write(manifest);
      } else {
        request.response.contentLength = size;
        for (var i = 0; i < size; i += chunk.length) {
          request.response.add(chunk);
          await request.response.flush();
        }
      }
    };
    final lease = (await open())!;
    final watch = Stopwatch()..start();
    final response =
        await (await client.getUrl(Uri.parse(segment(lease, 0)))).close();
    final received =
        await response.fold<int>(0, (total, data) => total + data.length);
    watch.stop();
    expect(received, size);
    expect(requests['/show/a.ts'], 1);
    // HTTP content-length completion may precede the final atomic disk commit.
    for (var i = 0; i < 100 && (await cache.list()).single['saved'] == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect((await cache.list()).single['saved'], 1);
    // A host-only observation, not a TV FPS/startup performance claim.
    // ignore: avoid_print
    print('16 MiB tee elapsedMs=${watch.elapsedMilliseconds}');
  });
}
