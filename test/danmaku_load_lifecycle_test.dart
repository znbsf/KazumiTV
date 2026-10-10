import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Downloads implements DownloadController {
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
        ResponseBody.fromString(jsonEncode({
          'comments': [
            {'p': '1.5,1,16777215,[Test]', 'm': message}
          ]
        }), 200, headers: {
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

  test('current manual request loads comments and stops loading', () async {
    final request = controller.getDanDanmakuByEpisodeID(1001);
    await requestStarted(1);
    expect(controller.danmakuLoading, isTrue);
    adapter.complete(0, 'current');
    expect(await request, isTrue);
    expect(controller.danDanmakus[1]!.single.message, 'current');
    expect(controller.danmakuLoading, isFalse);
  });

  test('cancelled manual request cannot repopulate a departed episode', () async {
    final request = controller.getDanDanmakuByEpisodeID(1001);
    await requestStarted(1);
    controller.finishDanmakuLoad();
    final rejected = expectLater(request, throwsA(isA<DanmakuLoadCancelled>()));
    adapter.complete(0, 'cancelled');
    await rejected;
    expect(controller.danDanmakus, isEmpty);
    expect(controller.danmakuLoading, isFalse);
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
