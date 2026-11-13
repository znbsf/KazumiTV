import 'package:kazumi/pages/video/video_controller.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/repositories/download_repository.dart';
import 'package:kazumi/services/download/download_manager.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Repository implements IDownloadRepository {
  _Repository(this.record);
  DownloadRecord record;
  @override
  DownloadRecord? getRecord(String key) => key == record.key ? record : null;
  @override
  List<DownloadRecord> getAllRecords() => [record];
  @override
  Future<void> putRecord(DownloadRecord value) async {
    record = value;
  }

  @override
  Future<void> updateEpisode(
      String key, int number, DownloadEpisode value) async {
    record.episodes[number] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Manager implements IDownloadManager {
  @override
  ProgressCallback? onProgress;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'same episode number preserves old path and persists a distinct task slot',
      () async {
    final root =
        await Directory.systemTemp.createTemp('kazumi_download_identity_');
    final previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.absolute.path);
    Hive.init(root.absolute.path);
    await GStorage.init();
    try {
      final old = DownloadEpisode(
          1,
          'season A ep 1',
          0,
          DownloadStatus.completed,
          1,
          1,
          1,
          'old/index.m3u8',
          'old',
          '',
          DateTime.utc(2026),
          '',
          1,
          'https://example.invalid/season-a/1');
      final repository = _Repository(DownloadRecord(
          123, 'synthetic', '', 'test', {1: old}, DateTime.utc(2026)));
      final controller =
          DownloadController(repository, _Manager(), PluginsController());
      await controller.startDownload(
        bangumiId: 123,
        bangumiName: 'synthetic',
        bangumiCover: '',
        pluginName: 'test',
        episodeNumber: 1,
        episodeName: 'season B ep 1',
        road: 0,
        episodePageUrl: 'https://example.invalid/season-b/1',
      );
      final current = repository.record.episodes[-1]!;
      expect(repository.record.episodes[1], same(old));
      expect(old.localM3u8Path, 'old/index.m3u8');
      expect(current.episodePageUrl, 'https://example.invalid/season-b/1');
      expect(current.episodeNumber, 1);
      expect(current.taskNumber, -1);
      await GStorage.downloads.put(repository.record.key, repository.record);
      final boxPath = GStorage.downloads.path!;
      await GStorage.downloads.close();
      GStorage.downloads = await Hive.openBox<DownloadRecord>('downloads',
          path: File(boxPath).parent.path);
      final restored = GStorage.downloads.get(repository.record.key)!;
      expect(restored.episodes[1]!.taskNumber, 1);
      expect(restored.episodes[-1]!.taskNumber, -1);
      expect(restored.episodes[1]!.localM3u8Path, 'old/index.m3u8');
      final roads =
          buildOfflineRoadListSnapshot(restored.episodes.values.toList());
      expect(roads.episodesByNumber.keys.toSet(), {1, -1});
      expect(roads.roads.single.data.toSet(), {'1', '-1'});
      final realRepository = DownloadRepository();
      expect(
          realRepository
              .getEpisodeByUrl(123, 'test', current.episodePageUrl)!
              .taskNumber,
          -1);
      await realRepository.deleteEpisode(repository.record.key, -1);
      expect(realRepository.getEpisode(123, 'test', 1)!.localM3u8Path,
          'old/index.m3u8');
    } finally {
      await Hive.close();
      PathProviderPlatform.instance = previousPaths;
      await root.delete(recursive: true);
    }
  });
}
