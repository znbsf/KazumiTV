import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/download/download_manager.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'issue37_download_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'legacy adapter bytes reopen and same-number downloads use isolated paths',
      () async {
    final root =
        await Directory.systemTemp.createTemp('kazumi_identity_paths_');
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = fixtures.Paths(root.path);
    Hive.init(root.path);
    await GStorage.init();
    final manager = DownloadManager();
    try {
      Hive.registerAdapter(LegacyDownloadEpisodeAdapter(), override: true);
      final old = DownloadEpisode(
          1,
          'old',
          0,
          DownloadStatus.completed,
          1,
          1,
          1,
          '${root.path}/legacy/video.mp4',
          '${root.path}/legacy',
          '',
          null,
          '',
          3,
          '');
      await Directory(old.downloadDirectory).create();
      await File(old.localM3u8Path).writeAsString('OLD');
      await GStorage.downloads.put('test_1',
          DownloadRecord(1, 'test', '', 'test', {1: old}, DateTime.utc(2026)));
      await GStorage.downloads.close();
      Hive.registerAdapter(DownloadEpisodeAdapter(), override: true);
      GStorage.downloads = await Hive.openBox<DownloadRecord>('downloads');
      final decoded = GStorage.downloads.get('test_1')!.episodes[1]!;
      expect(decoded.storageSlot, isNull);
      expect(decoded.taskNumber, 1);
      expect(manager.getLocalVideoPath(decoded), old.localM3u8Path);
      await GStorage.putSetting(SettingsKeys.downloadDirectory, root.path);
      DioFactory.downloadDio.httpClientAdapter = fixtures.Adapter(
          (request) async => ResponseBody.fromString('NEW', 200, headers: {
                'content-type': ['video/mp4'],
                'content-length': ['3']
              }));
      final newer = DownloadEpisode(1, 'season B', 0, DownloadStatus.pending, 0,
          0, 0, '', '', '', null, '', 0, 'https://fixture.invalid/season-b/1',
          storageSlot: -1);
      await manager.enqueue(DownloadRequest(
          recordKey: 'test_1',
          bangumiId: 1,
          pluginName: 'test',
          episodeNumber: -1,
          m3u8Url: 'https://fixture.invalid/video.mp4',
          httpHeaders: {},
          adBlockerEnabled: false,
          episode: newer));
      await fixtures.until(() => !manager.isDownloading('test_1', -1));
      expect(newer.status, DownloadStatus.completed);
      expect(newer.downloadDirectory, isNot(decoded.downloadDirectory));
      expect(await File(newer.localM3u8Path).readAsString(), 'NEW');
      await manager.deleteEpisodeFiles(1, 'test', -1, episode: newer);
      expect(await File(decoded.localM3u8Path).readAsString(), 'OLD');
      expect(await Directory(newer.downloadDirectory).exists(), false);
    } finally {
      DioFactory.downloadDio.close(force: true);
      DioFactory.reset();
      await Hive.close();
      PathProviderPlatform.instance = previous;
      await root.delete(recursive: true);
    }
  });
}

// Frozen adapter from TV 8b10e05d: writes exactly the original 16 fields.
class LegacyDownloadEpisodeAdapter extends TypeAdapter<DownloadEpisode> {
  @override
  final typeId = 8;

  @override
  DownloadEpisode read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DownloadEpisode(
      (fields[0] as num).toInt(),
      fields[1] as String,
      (fields[2] as num).toInt(),
      (fields[3] as num).toInt(),
      (fields[4] as num).toDouble(),
      (fields[5] as num).toInt(),
      (fields[6] as num).toInt(),
      fields[7] as String,
      fields[8] as String,
      fields[9] as String,
      fields[10] as DateTime?,
      fields[11] == null ? '' : fields[11] as String,
      fields[12] == null ? 0 : (fields[12] as num).toInt(),
      fields[13] == null ? '' : fields[13] as String,
      danmakuData: fields[14] == null ? '' : fields[14] as String,
      danDanBangumiID: fields[15] == null ? 0 : (fields[15] as num).toInt(),
    );
  }

  @override
  void write(BinaryWriter writer, DownloadEpisode obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.episodeNumber)
      ..writeByte(1)
      ..write(obj.episodeName)
      ..writeByte(2)
      ..write(obj.road)
      ..writeByte(3)
      ..write(obj.status)
      ..writeByte(4)
      ..write(obj.progressPercent)
      ..writeByte(5)
      ..write(obj.totalSegments)
      ..writeByte(6)
      ..write(obj.downloadedSegments)
      ..writeByte(7)
      ..write(obj.localM3u8Path)
      ..writeByte(8)
      ..write(obj.downloadDirectory)
      ..writeByte(9)
      ..write(obj.networkM3u8Url)
      ..writeByte(10)
      ..write(obj.completedAt)
      ..writeByte(11)
      ..write(obj.errorMessage)
      ..writeByte(12)
      ..write(obj.totalBytes)
      ..writeByte(13)
      ..write(obj.episodePageUrl)
      ..writeByte(14)
      ..write(obj.danmakuData)
      ..writeByte(15)
      ..write(obj.danDanBangumiID);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LegacyDownloadEpisodeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
