import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/repositories/download_repository.dart';
import 'package:kazumi/services/download/download_manager.dart';

DownloadEpisode episode(double progress,
        [int status = DownloadStatus.downloading]) =>
    DownloadEpisode(
        1, 'episode', 0, status, progress, 100, 0, '', '', '', null, '', 0, '');

class Repository implements IDownloadRepository {
  final data = <String, DownloadRecord>{
    for (final id in [1, 2])
      'test_$id': DownloadRecord(id, 'show', '', 'test',
          {1: episode(0, DownloadStatus.paused)}, DateTime.utc(2026)),
  };
  @override
  List<DownloadRecord> getAllRecords() => data.values.toList();
  @override
  DownloadRecord? getRecord(String key) => data[key];
  @override
  Future<void> updateEpisode(
      String key, int number, DownloadEpisode value) async {
    data[key]?.episodes[number] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Manager implements IDownloadManager {
  @override
  ProgressCallback? onProgress;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('interleaved records flush latest progress within 500 ms',
      (tester) async {
    final repository = Repository();
    final manager = Manager();
    final controller =
        DownloadController(repository, manager, PluginsController());
    await controller.init();
    for (var tick = 1; tick <= 3; tick++) {
      manager.onProgress!('test_1', 1, episode(tick / 10), 10);
      await tester.pump(const Duration(milliseconds: 100));
      manager.onProgress!('test_2', 1, episode(tick / 10), 20);
      manager.onProgress!('test_2', 1, episode(tick / 10 + .01), 25);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
          controller.getRecordSnapshot('test_1')!.episodes[1]!.progressPercent,
          tick / 10);
      expect(
          controller.getRecordSnapshot('test_2')!.episodes[1]!.progressPercent,
          tick / 10 + .01);
    }
  });

  testWidgets(
      'final states are immediate and a trailing flush cannot resurrect deletion',
      (tester) async {
    final repository = Repository();
    final manager = Manager();
    final controller =
        DownloadController(repository, manager, PluginsController());
    await controller.init();
    manager.onProgress!('test_1', 1, episode(.2), 10);
    manager.onProgress!('test_2', 1, episode(.3), 20);
    for (final status in [
      DownloadStatus.paused,
      DownloadStatus.failed,
      DownloadStatus.completed
    ]) {
      manager.onProgress!('test_1', 1, episode(.5, status), 0);
      expect(
          controller.getRecordSnapshot('test_1')!.episodes[1]!.status, status);
    }
    repository.data.remove('test_2');
    controller.refreshRecords();
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.getRecordSnapshot('test_2'), isNull);
    expect(controller.getRecordSnapshot('test_1')!.episodes[1]!.status,
        DownloadStatus.completed);
  });
}
