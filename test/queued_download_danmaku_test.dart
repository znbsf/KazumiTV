import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart' hide ProgressCallback;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/repositories/download_repository.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/download/download_manager.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'issue37_download_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'directory arriving after a 31 second queue still receives offline danmaku once',
      () async {
    final root =
        await Directory.systemTemp.createTemp('kazumi_queued_danmaku_');
    final original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = fixtures.Paths(root.path);
    Hive.init(root.path);
    await GStorage.init();
    await GStorage.putSetting(SettingsKeys.downloadDanmaku, true);
    await GStorage.putSetting(SettingsKeys.danmakuCacheEnabled, false);
    final episode = DownloadEpisode(2, 'queued', 0, DownloadStatus.pending, 0,
        0, 0, '', '', '', null, '', 0, 'https://fixture.invalid/2');
    final record =
        DownloadRecord(1, 'test', '', 'test', {2: episode}, DateTime.utc(2026));
    await GStorage.downloads.put(record.key, record);
    final repository = DownloadRepository();
    final manager = _Manager();
    final controller =
        DownloadController(repository, manager, PluginsController());
    final adapter = fixtures.Adapter((request) async => ResponseBody.fromString(
            jsonEncode(request.uri.path.contains('/comment/')
                ? {
                    'comments': [
                      {'p': '1,1,16777215,[fixture]', 'm': 'offline'}
                    ]
                  }
                : {
                    'success': true,
                    'errorCode': 0,
                    'errorMessage': '',
                    'bangumi': {'animeId': 99, 'episodes': []}
                  }),
            200,
            headers: {
              'content-type': ['application/json']
            }));
    DioFactory.apiDio.httpClientAdapter = adapter;
    try {
      await controller.init();
      episode.status = DownloadStatus.pending;
      manager.onProgress!(record.key, 2, episode, 0);
      await Future<void>.delayed(const Duration(seconds: 31));
      expect(adapter.requests, isEmpty);
      episode.downloadDirectory = '${root.path}/episode';
      await Directory(episode.downloadDirectory).create();
      episode.status = DownloadStatus.downloading;
      for (var i = 0; i < 5; i++) {
        manager.onProgress!(record.key, 2, episode, 0);
      }
      final file = File('${episode.downloadDirectory}/danmaku.json');
      await fixtures.until(() => file.existsSync() && file.lengthSync() > 0);
      episode.status = DownloadStatus.completed;
      manager.onProgress!(record.key, 2, episode, 0);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(adapter.requests, hasLength(2));
      expect((await controller.getCachedDanmakus(1, 'test', 2))!.single.message,
          'offline');
    } finally {
      DioFactory.apiDio.close(force: true);
      DioFactory.reset();
      await Hive.close();
      PathProviderPlatform.instance = original;
      await root.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(seconds: 45)));
}

class _Manager implements IDownloadManager {
  @override
  ProgressCallback? onProgress;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
