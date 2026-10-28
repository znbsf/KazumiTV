import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/repositories/download_repository.dart';
import 'package:kazumi/services/download/download_manager.dart';

class _Repository implements IDownloadRepository {
  _Repository(this.record);
  DownloadRecord record;
  final gate = Completer<void>();
  int writes = 0;
  @override
  List<DownloadRecord> getAllRecords() => [record];
  @override
  Future<void> putRecord(DownloadRecord record) async {
    writes++;
    if (writes == 1) await gate.future;
    this.record = record;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Manager implements IDownloadManager {
  @override
  ProgressCallback? onProgress;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('concurrent init waits for one reset and migration before callbacks',
      () async {
    final directory = await Directory.systemTemp.createTemp('kazumi_init_');
    try {
      final episode = DownloadEpisode(1, 'synthetic', 0, DownloadStatus.pending,
          0, 0, 0, '', directory.path, '', null, '', 0, '',
          danmakuData: '[]');
      final repository = _Repository(DownloadRecord(
          1, 'synthetic', '', 'test', {1: episode}, DateTime.utc(2026)));
      final manager = _Manager();
      final controller =
          DownloadController(repository, manager, PluginsController());
      final first = controller.init();
      final second = controller.init();
      expect(identical(first, second), isTrue);
      expect(manager.onProgress, isNull);
      expect(
          controller.records.single.episodes[1]!.status, DownloadStatus.paused);
      expect(episode.danmakuData, '[]');
      repository.gate.complete();
      await Future.wait([first, second]);
      expect(repository.record.episodes[1]!.danmakuData, '');
      expect(manager.onProgress, isNotNull);
      expect(repository.writes, 2); // reset, then migrate, once each
      expect((await directory.list().toList()).whereType<File>(), hasLength(1));
      await controller.init();
      expect(repository.writes, 2);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
