import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/recent_video_cache.dart';
import 'package:kazumi/services/player/recent_hls_manifest.dart';

void main() {
  late Directory directory;
  late HttpServer origin;
  late HttpClient client;
  late RecentVideoCache cache;
  late String base;
  late String playlist;
  late Map<String, List<int>> bodies;
  late List<String> ranges;
  late bool ignoreRange;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cache_formats_');
    cache = RecentVideoCache(directory, availableBytes: (_) async => 1 << 35);
    origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${origin.port}';
    client = HttpClient();
    ranges = [];
    ignoreRange = false;
    playlist = '#EXTM3U\n#EXTINF:5,\na.ts\n#EXT-X-ENDLIST\n';
    bodies = {
      '/a.ts': [1, 2, 3, 4],
      '/key': List.filled(16, 42),
      '/media.mp4': List.generate(32, (i) => i),
      '/init': [9, 8, 7, 6]
    };
    origin.listen((request) async {
      try {
        if (request.uri.path == '/list.m3u8') {
          request.response.write(playlist);
        } else {
          var bytes = bodies[request.uri.path]!;
          request.response.headers.contentType =
              request.uri.path.endsWith('.mp4')
                  ? ContentType('video', 'mp4')
                  : ContentType.binary;
          final range = request.headers.value('range');
          if (range != null && !ignoreRange) {
            ranges.add(range);
            final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
            final start = int.parse(match[1]!);
            final end =
                match[2]!.isEmpty ? bytes.length - 1 : int.parse(match[2]!);
            request.response.statusCode = 206;
            request.response.headers
                .set('Content-Range', 'bytes $start-$end/${bytes.length}');
            bytes = bytes.sublist(start, end + 1);
          }
          request.response.contentLength = bytes.length;
          if (request.method != 'HEAD') request.response.add(bytes);
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
  Future<Map<String, dynamic>> open({bool mp4 = false, String? proxy}) async =>
      (await cache.openOnline(
          identity: 'one',
          url:
              '${proxy == null ? base : 'http://unresolvable.invalid'}/${mp4 ? 'media.mp4' : 'list.m3u8'}',
          hls: !mp4,
          proxy: proxy,
          headers: {},
          metadata: {}))!;
  Future<(int, List<int>, String?)> get(String url, {String? range}) async {
    final request = await client.getUrl(Uri.parse(url));
    if (range != null) request.headers.set('Range', range);
    final result = await request.close();
    return (
      result.statusCode,
      await result.fold<List<int>>([], (a, b) => a..addAll(b)),
      result.headers.value('content-range')
    );
  }

  String resource(Map lease, int n) =>
      (lease['url'] as String).replaceFirst('playlist.m3u8', 's$n.ts');
  Future<Map<String, dynamic>> restartOffline(Map lease) async {
    await cache.release(lease['token']);
    await origin.close(force: true);
    cache = RecentVideoCache(directory, availableBytes: (_) async => 1 << 35);
    return (await cache.openOffline(lease['id']))!;
  }

  test('MP4 saves a full response, restarts offline and serves seeking ranges',
      () async {
    final lease = await open(mp4: true);
    expect(
        (await get(lease['url'], range: 'bytes=0-')).$2, bodies['/media.mp4']);
    final offline = await restartOffline(lease);
    final result = await get(offline['url'], range: 'bytes=8-15');
    expect(result.$1, 206);
    expect(result.$2, List.generate(8, (i) => i + 8));
    expect(result.$3, 'bytes 8-15/32');
  });

  test('MP4 partial seek is never marked complete', () async {
    final lease = await open(mp4: true);
    await get(lease['url'], range: 'bytes=8-15');
    expect((await cache.list()).single['complete'], false);
    expect(await cache.openOffline(lease['id']), isNull);
  });

  test('AES key rotation and init map all persist before offline eligibility',
      () async {
    playlist = '#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:7\n'
        '#EXT-X-KEY:METHOD=AES-128,URI="key",IV=0x01\n'
        '#EXT-X-MAP:URI="init"\n#EXTINF:5,\na.ts\n'
        '#EXT-X-KEY:METHOD=AES-128,URI="key"\n#EXTINF:5,\na.ts\n#EXT-X-ENDLIST\n';
    final lease = await open();
    final local = utf8.decode((await get(lease['url'])).$2);
    expect(local, contains('URI="s0.key",IV=0x01'));
    expect(local, contains('#EXT-X-MAP:URI="s1.mp4"'));
    for (var i = 0; i < 4; i++) {
      await get(resource(lease, i));
    }
    expect(await cache.openOffline(lease['id']), isNull);
    await get(resource(lease, 4));
    final offline = await restartOffline(lease);
    expect((await get(resource(offline, 0))).$2, bodies['/key']);
    expect((await get(resource(offline, 1))).$2, bodies['/init']);
    expect((await get(resource(offline, 4))).$2, bodies['/a.ts']);
  });

  test('invalid AES key length cannot yield an offline entry', () async {
    bodies['/key'] = [1, 2];
    playlist = playlist.replaceFirst(
        '#EXTINF', '#EXT-X-KEY:METHOD=AES-128,URI="key"\n#EXTINF');
    final lease = await open();
    await get(resource(lease, 0));
    await get(resource(lease, 1));
    expect(await cache.openOffline(lease['id']), isNull);
  });

  test('discontinuities and media bytes survive for native ad filtering',
      () async {
    playlist = '#EXTM3U\n#EXT-X-DISCONTINUITY-SEQUENCE:3\n'
        '#EXT-X-MEDIA-SEQUENCE:8\n#EXTINF:5,\na.ts\n'
        '#EXT-X-DISCONTINUITY\n#EXTINF:5,\na.ts\n#EXT-X-ENDLIST\n';
    final lease = await open();
    expect((await get(resource(lease, 0))).$2, bodies['/a.ts']);
    expect((await get(resource(lease, 1))).$2, bodies['/a.ts']);
    final offline = await restartOffline(lease);
    final manifest = utf8.decode((await get(offline['url'])).$2);
    expect(manifest, contains('#EXT-X-DISCONTINUITY-SEQUENCE:3\n'));
    expect(manifest, contains('#EXT-X-MEDIA-SEQUENCE:8\n'));
    expect(manifest, contains('#EXT-X-DISCONTINUITY\n'));
    expect(offline['total'], 2);
  });

  test('fMP4 segments retain the format suffix in the local manifest', () {
    final parsed = RecentHlsManifest.parse(
        '#EXTM3U\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:5,\npart.m4s\n#EXT-X-ENDLIST\n',
        Uri.parse(base),
        4096)!;
    expect(parsed.playlist, contains('URI="s0.mp4"'));
    expect(parsed.playlist, contains('\ns1.m4s\n'));
  });

  test(
      'range segments and maps are localized; explicit and implicit offsets survive restart',
      () async {
    playlist = '#EXTM3U\n#EXT-X-MAP:URI="init",BYTERANGE="2@1"\n'
        '#EXTINF:5,\n#EXT-X-BYTERANGE:2@0\na.ts\n'
        '#EXTINF:5,\n#EXT-X-BYTERANGE:2\na.ts\n#EXT-X-ENDLIST\n';
    final lease = await open();
    expect((await get(resource(lease, 0))).$2, [8, 7]);
    final partial = await get(resource(lease, 2), range: 'bytes=1-');
    expect(partial.$1, 206);
    expect(partial.$2, [4]);
    expect(partial.$3, 'bytes 1-1/2');
    expect((await cache.list()).single['saved'], 1);
    expect((await get(resource(lease, 1))).$2, [1, 2]);
    expect((await get(resource(lease, 2))).$2, [3, 4]);
    expect(ranges, ['bytes=1-2', 'bytes=3-3', 'bytes=0-1', 'bytes=2-3']);
    final offline = await restartOffline(lease);
    expect((await get(resource(offline, 2))).$2, [3, 4]);
    expect(utf8.decode((await get(offline['url'])).$2),
        isNot(contains('BYTERANGE')));
  });

  test('server ignoring a required source Range cannot poison offline cache',
      () async {
    ignoreRange = true;
    playlist =
        playlist.replaceFirst('#EXTINF', '#EXT-X-BYTERANGE:2@1\n#EXTINF');
    final lease = await open();
    expect((await get(resource(lease, 0))).$1, 502);
    expect(await cache.openOffline(lease['id']), isNull);
  });

  test('HTTP proxy carries both playlist and media, offline never uses proxy',
      () async {
    final lease = await open(proxy: 'PROXY 127.0.0.1:${origin.port}');
    expect((await get(resource(lease, 0))).$2, bodies['/a.ts']);
    final offline = await restartOffline(lease);
    expect((await get(resource(offline, 0))).$2, bodies['/a.ts']);
    expect(
        await File('${directory.path}/${lease['id']}/entry.json')
            .readAsString(),
        isNot(contains('unresolvable')));
  });

  test('unsupported and ambiguous HLS structures fail closed', () {
    for (final tags in [
      '#EXT-X-KEY:METHOD=SAMPLE-AES,URI="key"',
      '#EXT-X-KEY:METHOD=AES-128,URI="key",KEYFORMAT="drm"',
      '#EXT-X-KEY:METHOD=AES-128,URI="key",URI="other"',
      '#EXT-X-KEY:METHOD=AES-128,URI="key"\n#EXT-X-MAP:URI="init"',
      '#EXT-X-MAP:URI="init",BYTERANGE="2"',
      '#EXT-X-DEFINE:NAME="x",VALUE="a"',
      '#EXT-X-KEY:METHOD=AES-128,URI="key"\n#EXT-X-BYTERANGE:2@0',
      '#EXT-X-SESSION-KEY:METHOD=AES-128,URI="key"',
    ]) {
      expect(
          RecentHlsManifest.parse(
              playlist.replaceFirst('#EXTINF', '$tags\n#EXTINF'),
              Uri.parse(base),
              4096),
          isNull,
          reason: tags);
    }
  });
}
