import 'package:flutter_test/flutter_test.dart';
import 'package:mobx/mobx.dart';
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
  testWidgets(
      'record observers ignore unrelated progress and follow removal and re-add',
      (tester) async {
    final repository = Repository();
    final manager = Manager();
    final controller =
        DownloadController(repository, manager, PluginsController());
    await controller.init();
    var builds = 0;
    DownloadRecord? snapshot;
    final dispose = autorun((_) {
      builds++;
      snapshot = controller.getRecordSnapshot('test_1');
    });
    addTearDown(dispose.call);
    expect(builds, 1);
    manager.onProgress!('test_2', 1, episode(.2), 10);
    await tester.pump(const Duration(milliseconds: 500));
    expect(builds, 1);
    manager.onProgress!('test_1', 1, episode(.4), 10);
    await tester.pump(const Duration(milliseconds: 500));
    expect(builds, 2);
    expect(snapshot!.episodes[1]!.progressPercent, .4);
    final saved = repository.data.remove('test_1')!;
    controller.refreshRecords();
    expect(snapshot, isNull);
    repository.data['test_1'] = saved;
    controller.refreshRecords();
    expect(snapshot!.episodes[1]!.progressPercent, .4);
    manager.onProgress!('test_1', 1, episode(1, DownloadStatus.completed), 0);
    expect(snapshot!.episodes[1]!.status, DownloadStatus.completed);
  });

  testWidgets(
      'key subscriptions survive shared observers, switching and absent records',
      (tester) async {
    final repository = Repository();
    final manager = Manager();
    final controller =
        DownloadController(repository, manager, PluginsController());
    await controller.init();
    final key = Observable('test_1');
    var changes = 0;
    DownloadRecord? snapshot;
    final first = autorun((_) => controller.getRecordSnapshot('test_1'));
    final second = autorun((_) {
      snapshot = controller.getRecordSnapshot(key.value);
      changes++;
    });
    first();
    manager.onProgress!('test_1', 1, episode(.4, DownloadStatus.paused), 0);
    expect(changes, 2);
    runInAction(() => key.value = 'test_3');
    expect(snapshot, isNull);
    final before = changes;
    manager.onProgress!('test_1', 1, episode(.5, DownloadStatus.paused), 0);
    expect(changes, before);
    repository.data['test_3'] = DownloadRecord(
        3, 'new', '', 'test', {1: episode(0)}, DateTime.utc(2026));
    manager.onProgress!('test_3', 1, episode(1, DownloadStatus.completed), 0);
    expect(snapshot!.bangumiId, 3);
    second();
    var resumed = 0.0;
    final again = autorun((_) => resumed =
        controller.getRecordSnapshot('test_1')!.episodes[1]!.progressPercent);
    manager.onProgress!('test_1', 1, episode(.6, DownloadStatus.paused), 0);
    expect(resumed, .6);
    again();
    await tester.pump();
  });
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
