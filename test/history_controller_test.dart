import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/bangumi_tag.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:mobx/mobx.dart';

class _CountingRepository extends HistoryRepository {
  _CountingRepository(Box<History> box, bool Function() privateMode)
      : super(
          historiesBox: box,
          privateModeReader: privateMode,
          progressSyncAppender: (
              {required history,
              required episode,
              required road,
              required progressMs,
              required updatedAt}) async {},
          clearSyncAppender: () async {},
        );

  int fullReads = 0;
  @override
  List<History> getAllHistories() {
    fullReads++;
    return super.getAllHistories();
  }
}

BangumiItem _item(int id) => BangumiItem(
      id: id,
      type: 2,
      name: 'subject $id',
      nameCn: '',
      summary: '',
      airDate: '',
      airWeekday: 0,
      rank: 0,
      images: {},
      tags: [],
      alias: [],
      ratingScore: 0,
      votes: 0,
      votesCount: [],
      info: '',
    );

PlaybackHistoryIdentity _identity(int id, {bool offline = false}) =>
    PlaybackHistoryIdentity(
      bangumiItem: _item(id),
      pluginName: 'plugin',
      episodeNumber: 1,
      episodeTitle: 'EP1',
      road: 0,
      entryKind: offline ? HistoryEntryKind.offline : HistoryEntryKind.online,
    );

History _history(int id, DateTime time, {bool offline = false}) => History(
      _item(id),
      1,
      'plugin',
      time,
      '',
      'EP1',
      entryKind: offline ? HistoryEntryKind.offline : HistoryEntryKind.online,
    );

void main() {
  late Directory temp;
  late Box<History> box;
  late _CountingRepository repository;
  late HistoryController controller;
  var privateMode = false;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('history_incremental_');
    Hive.init(temp.path);
    Hive.registerAdapter(HistoryAdapter());
    Hive.registerAdapter(ProgressAdapter());
    Hive.registerAdapter(BangumiItemAdapter());
    Hive.registerAdapter(BangumiTagAdapter());
    box = await Hive.openBox<History>('histories');
  });
  setUp(() async {
    await box.clear();
    privateMode = false;
    repository = _CountingRepository(box, () => privateMode);
    controller = HistoryController(repository);
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  test('updates only the saved key and publishes one sorted snapshot',
      () async {
    final future = _history(3, DateTime(2100));
    final recent = _history(2, DateTime(2020));
    final old = _history(1, DateTime(2000));
    await box.putAll({
      for (final h in [old, future, recent]) h.key: h
    });
    controller.init();
    final snapshots = <List<int>>[];
    final dispose = autorun((_) {
      snapshots.add(controller.histories.map((h) => h.bangumiItem.id).toList());
    });
    addTearDown(dispose.call);
    await controller.updateHistory(_identity(1), const Duration(seconds: 10));
    expect(repository.fullReads, 1);
    expect(snapshots, [
      [3, 2, 1],
      [3, 1, 2]
    ]);
    expect(controller.histories.first, same(future));
    expect(controller.histories.last, same(recent));
    expect(controller.lastWatching(_item(1), 'plugin')!.progress,
        const Duration(seconds: 10));
    // Hive mutates the existing instance; unchanged order must still notify.
    await controller.updateHistory(_identity(1), const Duration(seconds: 20));
    expect(repository.fullReads, 1);
    expect(snapshots.length, 3);
    expect(controller.histories[1], same(old));
    expect(controller.histories[1].progresses[1]!.progress,
        const Duration(seconds: 20));
  });

  test('legacy dedup and online/offline identities survive incremental saves',
      () async {
    final legacy = _history(1, DateTime(2000));
    final scoped = _history(1, DateTime(2020));
    final offline = _history(1, DateTime(2021), offline: true);
    await box.putAll({
      History.legacyKey('plugin', _item(1)): legacy,
      scoped.key: scoped,
      offline.key: offline
    });
    controller.init();
    await controller.updateHistory(_identity(1), const Duration(seconds: 96),
        duration: const Duration(seconds: 100));
    await controller.updateHistory(
        _identity(1, offline: true), const Duration(seconds: 30));
    expect(repository.fullReads, 1);
    expect(controller.histories.length, 2);
    expect(controller.histories.map((h) => h.key).toSet().length, 2);
    expect(controller.findProgress(_item(1), 'plugin', 1)!.progress,
        Duration.zero);
    expect(
        controller
            .findProgress(_item(1), 'plugin', 1,
                entryKind: HistoryEntryKind.offline)!
            .progress,
        const Duration(seconds: 30));
  });

  test('new entries insert without full reads; private writes create no rows',
      () async {
    controller.init();
    privateMode = true;
    await controller.updateHistory(_identity(1), const Duration(seconds: 10));
    expect(controller.histories, isEmpty);
    privateMode = false;
    await controller.updateHistory(_identity(1), const Duration(seconds: 10));
    expect(controller.histories.single.key, History.getKey('plugin', _item(1)));
    expect(repository.fullReads, 1);
    await controller.clearAll();
    expect(controller.histories, isEmpty);
  });
}
