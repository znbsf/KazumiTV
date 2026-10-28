import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/download/download_manager.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class Paths extends PathProviderPlatform {
  Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class Adapter implements HttpClientAdapter {
  Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

DownloadEpisode episode(String path) => DownloadEpisode(1, 'Synthetic', 0,
    DownloadStatus.paused, 0, 0, 0, '', path, '', null, '', 0, '');
DownloadRequest request(String key, DownloadEpisode ep) => DownloadRequest(
    recordKey: key,
    bangumiId: 1,
    pluginName: 'synthetic',
    episodeNumber: 1,
    m3u8Url: 'https://fixture.invalid/$key',
    httpHeaders: {},
    adBlockerEnabled: false,
    episode: ep);
Future<void> until(bool Function() predicate) async {
  final watch = Stopwatch()..start();
  while (!predicate()) {
    if (watch.elapsed > const Duration(seconds: 5))
      throw TimeoutException('Fixture did not settle');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('HLS cancellation drains old workers before immediate retry', () async {
    final dir = await Directory.systemTemp.createTemp('kazumi_hls_cancel_');
    final late = Completer<ResponseBody>();
    var segmentCalls = 0;
    var completions = 0;
    final adapter = Adapter((options) async {
      if (options.uri.path.endsWith('.ts')) {
        if (++segmentCalls == 1) return late.future;
        return ResponseBody.fromString('NEW', 200);
      }
      return ResponseBody.fromString(
          '#EXTM3U\n#EXTINF:10,\npart.ts\n#EXT-X-ENDLIST\n', 200);
    });
    DioFactory.downloadDio.httpClientAdapter = adapter;
    final manager = DownloadManager()..maxParallelSegments = 1;
    final ep = episode(dir.path);
    manager.onProgress = (key, number, current, speed) {
      if (current.status == DownloadStatus.completed) completions++;
    };
    try {
      final req = request('hls-cancel', ep);
      await manager.enqueue(req);
      await until(() => segmentCalls == 1);
      manager.pause('hls-cancel', 1);
      final retry = manager.enqueue(req);
      late.complete(ResponseBody.fromString('OLD', 200));
      await retry;
      await until(() => !manager.isDownloading('hls-cancel', 1));
      expect(await File('${dir.path}/seg_00000.ts').readAsString(), 'NEW');
      expect(completions, 1);
      expect(segmentCalls, 2);
    } finally {
      await dir.delete(recursive: true);
    }
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late PathProviderPlatform previous;
  setUpAll(() async {
    Logger.level = Level.off;
    root = await Directory.systemTemp.createTemp('kazumi_review_');
    previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = Paths(root.path);
    Hive.init(root.path);
    await GStorage.init();
  });
  tearDown(() {
    DioFactory.downloadDio.close(force: true);
    DioFactory.reset();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = previous;
    final absolute = root.absolute.path;
    if (!absolute.startsWith(Directory.systemTemp.absolute.path) ||
        !root.uri.pathSegments
            .where((p) => p.isNotEmpty)
            .last
            .startsWith('kazumi_review_'))
      throw StateError('Unsafe fixture cleanup');
    await root.delete(recursive: true);
  });
  test(
      'resume must replace partial bytes when server ignores Range with HTTP 200',
      () async {
    final dir = await Directory('${root.path}/range').create();
    await File('${dir.path}/video.mp4.tmp').writeAsString('ABC');
    final adapter =
        Adapter((_) async => ResponseBody.fromString('ABCDEF', 200, headers: {
              'content-length': ['6']
            }));
    DioFactory.downloadDio.httpClientAdapter = adapter;
    final manager = DownloadManager();
    final ep = episode(dir.path);
    await manager.enqueue(request('range', ep));
    await until(() => !manager.isDownloading('range', 1));
    expect(ep.status, DownloadStatus.completed);
    expect(adapter.requests.last.headers['Range'], 'bytes=3-');
    final actual = await File('${dir.path}/video.mp4').readAsString();
    print('REVIEW range: completed file=$actual expected=ABCDEF');
    expect(actual, 'ABCDEF');
  });
  test('paused queued episode must run after retry through enqueue', () async {
    final held = Completer<ResponseBody>();
    final adapter = Adapter((options) async {
      if (options.uri.path == '/first') return held.future;
      return ResponseBody.fromString('#EXTM3U\n#EXT-X-ENDLIST\n', 200);
    });
    DioFactory.downloadDio.httpClientAdapter = adapter;
    final manager = DownloadManager()..maxParallelEpisodes = 1;
    final firstDir = await Directory('${root.path}/first').create();
    final secondDir = await Directory('${root.path}/second').create();
    final second = request('second', episode(secondDir.path));
    await manager.enqueue(request('first', episode(firstDir.path)));
    await until(() => adapter.requests.isNotEmpty);
    await manager.enqueue(second);
    manager.pause('second', 1);
    await manager.enqueue(second); // Production retryDownload uses this API.
    held.complete(ResponseBody.fromString('#EXTM3U\n#EXT-X-ENDLIST\n', 200));
    await until(() =>
        !manager.isDownloading('first', 1) &&
        !manager.isDownloading('second', 1));
    final paths = adapter.requests.map((r) => r.uri.path).toList();
    print('REVIEW queued retry: requested=$paths');
    expect(paths, contains('/second'));
  });
  test('HLS resume must not reuse numbered segment from a different manifest',
      () async {
    final dir = await Directory('${root.path}/hls').create();
    await File('${dir.path}/seg_00000.ts').writeAsString('OLD');
    final adapter = Adapter((options) async => options.uri.path.endsWith('.ts')
        ? ResponseBody.fromString('NEW', 200)
        : ResponseBody.fromString(
            '#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\nhttps://fixture.invalid/new-segment.ts\n#EXT-X-ENDLIST\n',
            200));
    DioFactory.downloadDio.httpClientAdapter = adapter;
    final manager = DownloadManager();
    final ep = episode(dir.path);
    await manager.enqueue(request('hls', ep));
    await until(() => !manager.isDownloading('hls', 1));
    expect(ep.status, DownloadStatus.completed);
    final actual = await File('${dir.path}/seg_00000.ts').readAsString();
    print(
        'REVIEW HLS: completed segment=$actual requests=${adapter.requests.length}');
    expect(actual, 'NEW');
  });

  for (final variant in [
    'valid',
    'wrong-start',
    'missing-range',
    'short',
    '416'
  ]) {
    test('direct resume validates $variant', () async {
      final dir = await Directory('${root.path}/$variant').create();
      await File('${dir.path}/video.mp4.tmp').writeAsString('ABC');
      var streams = 0;
      final adapter = Adapter((options) async {
        if (options.responseType != ResponseType.stream)
          return ResponseBody.fromString('video', 200);
        streams++;
        if (variant == '416') {
          if (streams == 1) return ResponseBody.fromString('', 416);
          expect(options.headers.containsKey('Range'), isFalse);
          return ResponseBody.fromString('ABCDEF', 200, headers: {
            'content-length': ['6']
          });
        }
        return ResponseBody.fromString(variant == 'short' ? 'D' : 'DEF', 206,
            headers: {
              'content-length': ['3'],
              if (variant != 'missing-range')
                'content-range': [
                  variant == 'wrong-start' ? 'bytes 2-4/5' : 'bytes 3-5/6'
                ],
            });
      });
      DioFactory.downloadDio.httpClientAdapter = adapter;
      final manager = DownloadManager();
      final ep = episode(dir.path);
      await manager.enqueue(request(variant, ep));
      await until(() => !manager.isDownloading(variant, 1));
      if (variant == 'valid' || variant == '416') {
        expect(ep.status, DownloadStatus.completed);
        expect(await File('${dir.path}/video.mp4').readAsString(), 'ABCDEF');
      } else {
        expect(ep.status, DownloadStatus.failed);
        expect(await File('${dir.path}/video.mp4').exists(), isFalse);
      }
      expect(streams, variant == '416' ? 2 : 1);
    });
  }

  test(
      'running pause retry duplicate clicks and late response preserve successor',
      () async {
    final dir = await Directory('${root.path}/race').create();
    final held = Completer<ResponseBody>();
    var calls = 0;
    final adapter = Adapter((options) async {
      if (++calls == 1) return held.future;
      return ResponseBody.fromString('ABCDEF', 200, headers: {
        'content-length': ['6']
      });
    });
    DioFactory.downloadDio.httpClientAdapter = adapter;
    final manager = DownloadManager();
    final ep = episode(dir.path);
    final req = request('race', ep);
    await manager.enqueue(req);
    await until(() => calls == 1);
    manager.pause('race', 1);
    final retries = [manager.enqueue(req), manager.enqueue(req)];
    held.complete(ResponseBody.fromString('OLD', 200));
    await Future.wait(retries);
    await until(() => !manager.isDownloading('race', 1));
    expect(ep.status, DownloadStatus.completed);
    expect(await File('${dir.path}/video.mp4').readAsString(), 'ABCDEF');
    expect(calls, 3); // retired probe, new probe, new stream
  });

  test('cancelled direct response never publishes completed', () async {
    final dir = await Directory('${root.path}/cancel').create();
    final held = Completer<ResponseBody>();
    var streaming = false;
    final adapter = Adapter((options) async {
      if (options.responseType != ResponseType.stream)
        return ResponseBody.fromString('video', 200);
      streaming = true;
      return held.future;
    });
    DioFactory.downloadDio.httpClientAdapter = adapter;
    final manager = DownloadManager();
    final ep = episode(dir.path);
    await manager.enqueue(request('cancel', ep));
    await until(() => streaming);
    manager.cancel('cancel', 1);
    held.complete(ResponseBody.fromString('late', 200));
    await until(() => !manager.isDownloading('cancel', 1));
    expect(ep.status, isNot(DownloadStatus.completed));
    expect(await File('${dir.path}/video.mp4').exists(), isFalse);
  });

  test(
      'HLS receipts permit exact resume and reject changed manifest config or bytes',
      () async {
    final dir = await Directory('${root.path}/identity').create();
    var uri = 'one.ts';
    final adapter = Adapter((options) async => options.uri.path.endsWith('.ts')
        ? ResponseBody.fromString('SEG', 200)
        : ResponseBody.fromString(
            '#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\n$uri\n#EXT-X-ENDLIST\n',
            200));
    DioFactory.downloadDio.httpClientAdapter = adapter;
    final manager = DownloadManager();
    final ep = episode(dir.path);
    Future<void> run({bool ads = false}) async {
      await manager.enqueue(DownloadRequest(
          recordKey: 'identity',
          bangumiId: 1,
          pluginName: 'synthetic',
          episodeNumber: 1,
          m3u8Url: 'https://fixture.invalid/identity',
          httpHeaders: {},
          adBlockerEnabled: ads,
          episode: ep));
      await until(() => !manager.isDownloading('identity', 1));
      expect(ep.status, DownloadStatus.completed);
    }

    int segments() =>
        adapter.requests.where((r) => r.uri.path.endsWith('.ts')).length;
    await run();
    expect(segments(), 1);
    await run();
    expect(segments(), 1);
    await File('${dir.path}/seg_00000.ts').writeAsString('BAD');
    await run();
    expect(segments(), 2);
    uri = 'two.ts';
    await run();
    expect(segments(), 3);
    await run(ads: true);
    expect(segments(), 4);
    await File('${dir.path}/seg_00000.ts.identity').writeAsString('broken');
    await run(ads: true);
    expect(segments(), 5);
  });
}
