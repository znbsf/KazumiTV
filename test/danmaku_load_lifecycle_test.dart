import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Downloads implements DownloadController {
  Future<List<DanmakuEntry>?>? cached;
  int writes = 0;

  @override
  Future<List<DanmakuEntry>?> getCachedDanmakus(
          int bangumiId, String pluginName, int episode) async =>
      await cached;

  @override
  Future<void> updateCachedDanmakus(int bangumiId, String pluginName,
      int episode, List<DanmakuEntry> danmakus, int danDanBangumiID) async {
    writes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _PendingComments implements HttpClientAdapter {
  final requests = <Completer<ResponseBody>>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    final pending = Completer<ResponseBody>();
    requests.add(pending);
    return pending.future;
  }

  void complete(int index, String message) => requests[index].complete(
        ResponseBody.fromString(
            jsonEncode({
              'comments': [
                {'p': '1.5,1,16777215,[Test]', 'm': message}
              ]
            }),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json']
            }),
      );

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform previousPaths;
  late _PendingComments adapter;
  late PlayerDanmakuController controller;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('kazumi_danmaku_life_');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });
  setUp(() {
    DioFactory.reset();
    adapter = _PendingComments();
    DioFactory.apiDio.httpClientAdapter = adapter;
    controller = PlayerDanmakuController(
        isLocalPlayback: () => false, downloadController: _Downloads());
  });
  tearDown(() {
    DioFactory.apiDio.close(force: true);
    DioFactory.reset();
  });
  tearDownAll(() async {
    await flushLogs();
    await Hive.close();
    PathProviderPlatform.instance = previousPaths;
    expect(directory.parent.absolute.path, Directory.systemTemp.absolute.path);
    expect(directory.path.split(Platform.pathSeparator).last,
        startsWith('kazumi_danmaku_life_'));
    await directory.delete(recursive: true);
  });

  Future<void> requestStarted(int count) async {
    for (var i = 0; i < 100 && adapter.requests.length < count; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(adapter.requests.length, count);
  }

  for (final local in [false, true]) {
    for (final status in [429, 403, 500]) {
      test('automatic local=$local HTTP $status preserves failure guidance',
          () async {
        controller = PlayerDanmakuController(
            isLocalPlayback: () => local, downloadController: _Downloads());
        final request = controller.fetchDanmaku(100, 'fixture', 1);
        await requestStarted(1);
        adapter.requests.single.complete(ResponseBody.fromString('{}', status));
        final result = await request;
        expect(result.isFailed, isTrue);
        expect(result.failure?.statusCode, status);
        expect(result.failureMessage.contains('手动检索'), status != 429);
        expect(result.failureMessage.contains('避免连续重试'), status == 429);
        expect(adapter.requests, hasLength(1));
      });
    }
  }

  test('automatic comment 429 keeps status after successful matching',
      () async {
    final request = controller.fetchDanmaku(100, 'fixture', 1);
    await requestStarted(1);
    adapter.requests[0].complete(ResponseBody.fromString(
        jsonEncode({
          'bangumi': {'animeId': 123, 'episodes': []},
          'errorCode': 0,
          'success': true,
          'errorMessage': ''
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        }));
    await requestStarted(2);
    adapter.requests[1].complete(ResponseBody.fromString('{}', 429));
    final result = await request;
    expect(result.bangumiID, 123);
    expect(result.failure?.statusCode, 429);
    expect(result.failureMessage, isNot(contains('手动检索')));
    expect(adapter.requests, hasLength(2));
  });

  test('current manual request loads comments and stops loading', () async {
    final request = controller.getDanDanmakuByEpisodeID(1001);
    await requestStarted(1);
    expect(controller.danmakuLoading, isTrue);
    adapter.complete(0, 'current');
    expect(await request, isTrue);
    expect(controller.danDanmakus[1]!.single.message, 'current');
    expect(controller.danmakuLoading, isFalse);
  });

  for (final local in [false, true]) {
    test('cancelled automatic local=$local mapping sends no comment request',
        () async {
      controller = PlayerDanmakuController(
          isLocalPlayback: () => local, downloadController: _Downloads());
      controller.beginDanmakuLoad();
      final result = controller
          .fetchDanmaku(100, 'fixture', 1)
          .then<Object>((value) => value, onError: (Object error) => error);
      await requestStarted(1);
      controller.finishDanmakuLoad();
      controller.beginDanmakuLoad();
      adapter.requests[0].complete(ResponseBody.fromString(
          jsonEncode({
            'bangumi': {'animeId': 123, 'episodes': []},
            'errorCode': 0,
            'success': true,
            'errorMessage': ''
          }),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          }));
      // Drain the old continuation and also finish a wrong second request so
      // the pre-fix failure reports an assertion rather than a timeout.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      if (adapter.requests.length > 1) adapter.complete(1, 'obsolete');
      expect(await result, isA<DanmakuLoadCancelled>());
      expect(adapter.requests, hasLength(1));
      expect(controller.danmakuLoading, isTrue);
      expect(controller.danDanmakus, isEmpty);
    });
  }

  test('cancelled manual request cannot repopulate a departed episode',
      () async {
    final request = controller.getDanDanmakuByEpisodeID(1001);
    await requestStarted(1);
    controller.finishDanmakuLoad();
    final rejected = expectLater(request, throwsA(isA<DanmakuLoadCancelled>()));
    adapter.complete(0, 'cancelled');
    await rejected;
    expect(controller.danDanmakus, isEmpty);
    expect(controller.danmakuLoading, isFalse);
  });

  test('cancelled cache lookup cannot start an online fallback', () async {
    final pending = Completer<List<DanmakuEntry>?>();
    final downloads = _Downloads()..cached = pending.future;
    controller = PlayerDanmakuController(
        isLocalPlayback: () => true, downloadController: downloads);
    controller.beginDanmakuLoad();
    final request = controller.fetchDanmaku(100, 'fixture', 1);
    final rejected = expectLater(request, throwsA(isA<DanmakuLoadCancelled>()));
    controller.finishDanmakuLoad();
    pending.complete(null);
    await rejected;
    expect(adapter.requests, isEmpty);
    expect(downloads.writes, 0);
  });

  test('late automatic HTTP failure is cancellation, not retry guidance',
      () async {
    controller.beginDanmakuLoad();
    final request = controller.fetchDanmaku(100, 'fixture', 1);
    await requestStarted(1);
    final rejected = expectLater(request, throwsA(isA<DanmakuLoadCancelled>()));
    controller.finishDanmakuLoad();
    controller.beginDanmakuLoad();
    adapter.requests[0].complete(ResponseBody.fromString('{}', 429));
    await rejected;
    expect(controller.danmakuLoading, isTrue);
    expect(adapter.requests, hasLength(1));
  });

  test('old manual response cannot end a new automatic episode load', () async {
    final request = controller.getDanDanmakuByEpisodeID(1001);
    await requestStarted(1);
    controller.finishDanmakuLoad();
    controller.beginDanmakuLoad();
    final rejected = expectLater(request, throwsA(isA<DanmakuLoadCancelled>()));
    adapter.complete(0, 'old episode');
    await rejected;
    expect(controller.danDanmakus, isEmpty);
    expect(controller.danmakuLoading, isTrue);
  });

  test('reversed manual completions keep only the newest selection', () async {
    final older = controller.getDanDanmakuByEpisodeID(1001);
    await requestStarted(1);
    final newer = controller.getDanDanmakuByEpisodeID(1002);
    await requestStarted(2);
    adapter.complete(1, 'new selection');
    expect(await newer, isTrue);
    final rejected = expectLater(older, throwsA(isA<DanmakuLoadCancelled>()));
    adapter.complete(0, 'old selection');
    await rejected;
    expect(controller.danDanmakus[1]!.map((e) => e.message), ['new selection']);
    expect(controller.danmakuLoading, isFalse);
  });

  test('cancelling an old dialog leaves a newer episode load active', () async {
    final request = controller.getDanDanmakuByEpisodeID(1001);
    await requestStarted(1);
    final oldGeneration = controller.danmakuLoadGeneration;
    controller.beginDanmakuLoad();
    controller.cancelDanmakuLoadIfCurrent(oldGeneration);
    expect(controller.danmakuLoading, isTrue);
    final rejected = expectLater(request, throwsA(isA<DanmakuLoadCancelled>()));
    adapter.complete(0, 'old dialog');
    await rejected;
    expect(controller.danmakuLoading, isTrue);
  });

  test('late network failure cannot finish the next load', () async {
    final request = controller.getDanDanmakuByEpisodeID(1001);
    await requestStarted(1);
    controller.beginDanmakuLoad();
    final rejected = expectLater(request, throwsA(isA<DanmakuLoadCancelled>()));
    adapter.requests[0].complete(ResponseBody.fromString('failure', 500));
    await rejected;
    expect(controller.danDanmakus, isEmpty);
    expect(controller.danmakuLoading, isTrue);
  });
}
