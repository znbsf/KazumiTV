import 'package:kazumi/modules/bangumi/bangumi_collection.dart';
import 'package:kazumi/modules/bangumi/sync_priority.dart';
import 'package:kazumi/modules/collect/collect_change_module.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_type_mapper.dart';

class CollectiblesMergeResult {
  const CollectiblesMergeResult({
    required this.collectibles,
    required this.changes,
  });

  final List<CollectedBangumi> collectibles;
  final List<CollectedBangumiChange> changes;
}

class BangumiUploadMutation {
  const BangumiUploadMutation({
    required this.bangumiId,
    required this.type,
  });

  final int bangumiId;
  final int type;
}

class BangumiLocalMutation {
  const BangumiLocalMutation({
    required this.collectible,
    required this.changeAction,
  });

  final CollectedBangumi collectible;
  final int changeAction;
}

class BangumiCollectiblesMergePlan {
  const BangumiCollectiblesMergePlan({
    required this.localOnlyUploads,
    required this.remoteOnlyPuts,
    required this.conflictUploads,
    required this.conflictLocalUpdates,
  });

  final List<BangumiUploadMutation> localOnlyUploads;
  final List<BangumiLocalMutation> remoteOnlyPuts;
  final List<BangumiUploadMutation> conflictUploads;
  final List<BangumiLocalMutation> conflictLocalUpdates;

  int get totalOperations =>
      localOnlyUploads.length +
      remoteOnlyPuts.length +
      conflictUploads.length +
      conflictLocalUpdates.length;
}

class CollectSyncMerger {
  static CollectiblesMergeResult mergeWebDav({
    required List<CollectedBangumi> localCollectibles,
    required List<CollectedBangumiChange> localChanges,
    required List<CollectedBangumi> remoteCollectibles,
    required List<CollectedBangumiChange> remoteChanges,
  }) {
    // IDs in legacy boxes are only device-local seconds/counters. Compare the
    // operation itself, including its time, so remapped IDs remain idempotent.
    String identity(CollectedBangumiChange c) =>
        '${c.timestamp}:${c.bangumiID}:${c.action}:${c.type}';
    final operations = <String, CollectedBangumiChange>{};
    for (final c in [...remoteChanges, ...localChanges]) {
      final old = operations[identity(c)];
      if (old == null || c.id < old.id) operations[identity(c)] = c;
    }
    final ordered = operations.values.toList()
      ..sort((a, b) {
        final time = a.timestamp.compareTo(b.timestamp);
        return time != 0 ? time : identity(a).compareTo(identity(b));
      });
    final used = <int>{};
    final reserved = ordered.map((c) => c.id).toSet();
    var next = 0;
    final changes = <CollectedBangumiChange>[];
    for (final c in ordered) {
      var id = c.id;
      if (used.contains(id)) {
        while (reserved.contains(next) || used.contains(next)) {
          next++;
        }
        if (next > 0xffffffff)
          throw StateError('Collection change IDs exhausted');
        id = next++;
      }
      used.add(id);
      changes.add(CollectedBangumiChange(
          id, c.bangumiID, c.action, c.type, c.timestamp));
    }
    final items = <int, CollectedBangumi>{};
    for (final item in [...remoteCollectibles, ...localCollectibles]) {
      final old = items[item.bangumiItem.id];
      if (old == null || item.time.isAfter(old.time)) {
        items[item.bangumiItem.id] = _copyCollectible(item);
      }
    }
    // Replaying all operations makes merging independent of device order and
    // preserves tombstones when an offline device brings an older snapshot.
    for (final c in changes) {
      if (c.action == 3) {
        items.remove(c.bangumiID);
      } else if (c.action == 1 || c.action == 2) {
        final source = _findCollectible(localCollectibles, c.bangumiID) ??
            _findCollectible(remoteCollectibles, c.bangumiID);
        if (source != null) {
          items[c.bangumiID] = CollectedBangumi(source.bangumiItem,
              DateTime.fromMillisecondsSinceEpoch(c.timestamp * 1000), c.type);
        }
      }
    }
    final result = items.values.toList()
      ..sort((a, b) => a.bangumiItem.id.compareTo(b.bangumiItem.id));
    return CollectiblesMergeResult(collectibles: result, changes: changes);
  }

  static BangumiCollectiblesMergePlan planBangumi({
    required List<CollectedBangumi> localCollectibles,
    required List<BangumiCollection> remoteCollections,
    required BangumiSyncPriority priority,
  }) {
    final localMap = {
      for (final item in localCollectibles) item.bangumiItem.id: item,
    };
    final remoteMap = <int, BangumiCollection>{};
    for (final item in remoteCollections) {
      final remoteCollectType = item.type.toCollectType();
      if (!remoteCollectType.isCollected) {
        continue;
      }
      remoteMap[item.bangumiId] = item;
    }

    final localOnlyIds = localMap.keys
        .toSet()
        .difference(remoteMap.keys.toSet())
        .toList()
      ..sort();
    final remoteOnlyIds = remoteMap.keys
        .toSet()
        .difference(localMap.keys.toSet())
        .toList()
      ..sort();
    final sharedIds = localMap.keys
        .toSet()
        .intersection(remoteMap.keys.toSet())
        .toList()
      ..sort();
    final mismatchIds = <int>[];
    for (final id in sharedIds) {
      if (localMap[id]!.type != remoteMap[id]!.type.toCollectType().value) {
        mismatchIds.add(id);
      }
    }

    final localOnlyUploads = [
      for (final id in localOnlyIds)
        BangumiUploadMutation(bangumiId: id, type: localMap[id]!.type),
    ];
    final remoteOnlyPuts = [
      for (final id in remoteOnlyIds)
        BangumiLocalMutation(
          collectible: _fromBangumiCollection(remoteMap[id]!),
          changeAction: 1,
        ),
    ];

    final conflictUploads = <BangumiUploadMutation>[];
    final conflictLocalUpdates = <BangumiLocalMutation>[];
    if (priority == BangumiSyncPriority.localFirst) {
      for (final id in mismatchIds) {
        conflictUploads.add(
          BangumiUploadMutation(bangumiId: id, type: localMap[id]!.type),
        );
      }
    } else if (priority == BangumiSyncPriority.bangumiFirst) {
      for (final id in mismatchIds) {
        conflictLocalUpdates.add(
          BangumiLocalMutation(
            collectible: _fromBangumiCollection(remoteMap[id]!),
            changeAction: 2,
          ),
        );
      }
    } else if (priority == BangumiSyncPriority.timeFirst) {
      for (final id in mismatchIds) {
        final localTime = localMap[id]!.time;
        final remoteTime = remoteMap[id]!.updatedAt;
        if (localTime.isAfter(remoteTime) ||
            localTime.isAtSameMomentAs(remoteTime)) {
          conflictUploads.add(
            BangumiUploadMutation(bangumiId: id, type: localMap[id]!.type),
          );
        } else {
          conflictLocalUpdates.add(
            BangumiLocalMutation(
              collectible: _fromBangumiCollection(remoteMap[id]!),
              changeAction: 2,
            ),
          );
        }
      }
    }

    return BangumiCollectiblesMergePlan(
      localOnlyUploads: localOnlyUploads,
      remoteOnlyPuts: remoteOnlyPuts,
      conflictUploads: conflictUploads,
      conflictLocalUpdates: conflictLocalUpdates,
    );
  }

  static CollectedBangumi _fromBangumiCollection(BangumiCollection remote) {
    final localType = remote.type.toCollectType();
    return CollectedBangumi(
      remote.toBangumiItem(),
      remote.updatedAt,
      localType.value,
    );
  }

  static CollectedBangumi? _findCollectible(
    List<CollectedBangumi> collectibles,
    int bangumiId,
  ) {
    for (final collectible in collectibles) {
      if (collectible.bangumiItem.id == bangumiId) {
        return collectible;
      }
    }
    return null;
  }

  static CollectedBangumi _copyCollectible(CollectedBangumi collectible) {
    return CollectedBangumi(
      collectible.bangumiItem,
      collectible.time,
      collectible.type,
    );
  }

  CollectSyncMerger._();
}
