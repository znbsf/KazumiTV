import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/recent_video_cache.dart';

void main() {
  const length = 64 * 1024 * 1024;
  final beginning = List.generate(64, (i) => 255 - i);
  final ending = List.generate(64, (i) => i);
  late Directory directory;
  late RecentVideoCache cache;
  late HttpClient client;
  late String id;

  setUp(() async {
    directory =
        await Directory.systemTemp.createTemp('cache_range_concurrency_');
    id = RecentVideoCache.keyFor('synthetic-complete-file');
    final entry = await Directory('${directory.path}/$id').create();
    final file = await File('${entry.path}/s0.ts').open(mode: FileMode.write);
    await file.writeFrom(beginning);
    await file.setPosition(length - ending.length);
    await file.writeFrom(ending);
    await file.close();
    cache = RecentVideoCache(directory, availableBytes: (_) async => 1 << 36);
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await cache.close().timeout(const Duration(seconds: 3));
    await directory.delete(recursive: true);
  });

  Future<Map<String, dynamic>> open(
      {bool hls = false, bool online = false}) async {
    await File('${directory.path}/$id/entry.json').writeAsString(jsonEncode({
      'version': 1,
      'fingerprint': 'synthetic',
      'playlist': hls ? '#EXTM3U\n#EXTINF:60,\ns0.ts\n#EXT-X-ENDLIST\n' : '',
      'lengths': [length],
      'metadata': {},
      'accessed': 0,
      'danmakuBytes': 0,
    }));
    return (online
        ? await cache.openOnline(
            identity: 'synthetic-complete-file',
            url: 'http://origin.invalid/media.mp4',
            hls: false,
            headers: {},
            metadata: {})
        : await cache.openOffline(id))!;
  }

  Future<(Socket, StreamSubscription<List<int>>)> holdReader(Uri uri) async {
    final socket = await Socket.connect(uri.host, uri.port);
    final ready = Completer<void>();
    final header = <int>[];
    late StreamSubscription<List<int>> subscription;
    subscription = socket.listen((data) {
      header.addAll(data.take(4096));
      if (!ready.isCompleted && latin1.decode(header).contains('\r\n\r\n')) {
        subscription.pause();
        ready.complete();
      }
    }, onError: (Object error) {
      if (!ready.isCompleted) ready.completeError(error);
    });
    socket.write('GET ${uri.path} HTTP/1.1\r\nHost: ${uri.host}\r\n'
        'Range: bytes=0-\r\nConnection: close\r\n\r\n');
    await socket.flush();
    try {
      await ready.future.timeout(const Duration(seconds: 2));
      return (socket, subscription);
    } catch (_) {
      socket.destroy();
      await subscription.cancel();
      rethrow;
    }
  }

  Future<void> expectRange(Uri uri, int start, List<int> expected) async {
    final request = await client.getUrl(uri);
    final end = start + expected.length - 1;
    request.headers.set('Range', 'bytes=$start-$end');
    final response = await request.close();
    expect(response.statusCode, 206);
    expect(
        response.headers.value('content-range'), 'bytes $start-$end/$length');
    expect(await response.fold<List<int>>([], (all, data) => all..addAll(data)),
        expected);
  }

  for (final scenario in [
    'offline MP4',
    'online complete MP4 hit',
    'offline HLS'
  ]) {
    test('$scenario seeks both ways while the old reader is still open',
        () async {
      final lease = await open(
          hls: scenario == 'offline HLS',
          online: scenario.startsWith('online'));
      final uri = Uri.parse(
          (lease['url'] as String).replaceFirst('playlist.m3u8', 's0.ts'));
      final (socket, subscription) = await holdReader(uri);
      try {
        // The replacement request must finish without closing the old reader.
        await expectRange(uri, length - ending.length, ending)
            .timeout(const Duration(seconds: 2));
        await expectRange(uri, 0, beginning)
            .timeout(const Duration(seconds: 2));
        final head = await client.openUrl('HEAD', uri);
        final response = await head.close().timeout(const Duration(seconds: 2));
        expect(response.statusCode, 200);
        expect(response.contentLength, length);
        await response.drain<void>();
      } finally {
        socket.destroy();
        await subscription.cancel();
      }
    });
  }

  test('release aborts overlapping cached readers and retires the lease',
      () async {
    final lease = await open();
    final survivor = (await cache.openOffline(id))!;
    final uri = Uri.parse(lease['url']);
    final first = await holdReader(uri);
    final second = await holdReader(uri);
    try {
      await cache.release(lease['token']).timeout(const Duration(seconds: 3));
      final response = await (await client.getUrl(uri)).close();
      expect(response.statusCode, 404);
      await response.drain<void>();
      await cache.release(survivor['token']);
      await cache.clear(id: id);
      expect(await cache.list(), isEmpty);
    } finally {
      first.$1.destroy();
      second.$1.destroy();
      await first.$2.cancel();
      await second.$2.cancel();
    }
  });
}
