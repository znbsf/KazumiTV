import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:mobx/mobx.dart';

part 'history_controller.g.dart';

class HistoryController = _HistoryController with _$HistoryController;

abstract class _HistoryController with Store {
  _HistoryController(this._historyRepository);

  final IHistoryRepository _historyRepository;

  @observable
  ObservableList<History> histories = ObservableList<History>();

  void init() {
    final temp = _historyRepository.getAllHistories();
    runInAction(() {
      histories.clear();
      histories.addAll(temp);
    });
  }

  Future<void> updateHistory(
    PlaybackHistoryIdentity identity,
    Duration progress, {
    Duration duration = Duration.zero,
  }) async {
    await _historyRepository.updateHistory(
      identity: identity,
      progress: progress,
      duration: duration,
    );
    // Read back the persisted value (including near-end normalization), not
    // the requested progress. A private-mode/invalid write may save nothing.
    final saved = _historyRepository.getHistory(
      identity.pluginName,
      identity.bangumiItem,
      entryKind: identity.entryKind,
    );
    if (saved == null) return;
    runInAction(() {
      // Hive can mutate the same History instance already in the list.
      // Remove/insert also notifies observers when only its progress changed.
      histories.removeWhere((entry) => entry.key == saved.key);
      final index = histories.indexWhere(
        (entry) => entry.lastWatchTime.isBefore(saved.lastWatchTime),
      );
      histories.insert(index < 0 ? histories.length : index, saved);
    });
  }

  Progress? lastWatching(
    BangumiItem bangumiItem,
    String adapterName, {
    String entryKind = HistoryEntryKind.online,
  }) {
    return _historyRepository.getLastWatchingProgress(
      bangumiItem,
      adapterName,
      entryKind: entryKind,
    );
  }

  History? getHistory(BangumiItem bangumiItem, String adapterName) {
    return _historyRepository.getHistory(adapterName, bangumiItem);
  }

  Progress? findProgress(
    BangumiItem bangumiItem,
    String adapterName,
    int episode, {
    String entryKind = HistoryEntryKind.online,
  }) {
    return _historyRepository.findProgress(
      bangumiItem,
      adapterName,
      episode,
      entryKind: entryKind,
    );
  }

  Future<void> deleteHistory(History history) async {
    await _historyRepository.deleteHistory(history);
    init();
  }

  Future<void> clearAll() async {
    await _historyRepository.clearAllHistories();
    runInAction(histories.clear);
  }
}
