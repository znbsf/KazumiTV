import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:kazumi/modules/collect/collect_change_module.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/modules/history/history_sync.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/async_serial_queue.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class LocalLibraryBackupException implements Exception {
  const LocalLibraryBackupException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

/// These are detached copies of the existing business boxes, never new boxes.
class LocalLibrarySnapshot {
  LocalLibrarySnapshot({
    required this.collections,
    required this.histories,
    required this.changes,
  });

  final Map<dynamic, CollectedBangumi> collections;
  final Map<dynamic, History> histories;
  final Map<dynamic, CollectedBangumiChange> changes;

  Map<String, dynamic> _toJson() => {
        'collections':
            _rows(collections, LocalLibraryArchiveCodec.collectionJson),
        'histories': _rows(histories, HistorySyncCodec.historyToJson),
        'changes': _rows(
            changes,
            (value) => {
                  'id': value.id,
                  'bangumiId': value.bangumiID,
                  'action': value.action,
                  'type': value.type,
                  'timestamp': value.timestamp,
                }),
      };

  static List<Map<String, dynamic>> _rows<T>(
      Map<dynamic, T> values, Map<String, dynamic> Function(T) encode) {
    final entries = values.entries.toList()
      ..sort((a, b) => _key(a.key).compareTo(_key(b.key)));
    return [
      for (final entry in entries)
        {'key': entry.key, 'value': encode(entry.value)},
    ];
  }

  static String _key(dynamic key) {
    if (key is! String && key is! int) {
      throw const LocalLibraryBackupException('invalid', '本地记录键损坏，已停止操作。');
    }
    return '${key is int ? 'i' : 's'}:$key';
  }

  String get fingerprint =>
      sha256.convert(utf8.encode(_canonicalJson(_toJson()))).toString();

  LocalLibrarySnapshot detached() {
    return LocalLibrarySnapshot(
      collections: {
        for (final entry in collections.entries)
          entry.key: LocalLibraryArchiveCodec.collection(
              LocalLibraryArchiveCodec.collectionJson(entry.value)),
      },
      histories: {
        for (final entry in histories.entries)
          entry.key: LocalLibraryArchiveCodec.history(
              HistorySyncCodec.historyToJson(entry.value)),
      },
      changes: {
        for (final entry in changes.entries)
          entry.key: CollectedBangumiChange(
              entry.value.id,
              entry.value.bangumiID,
              entry.value.action,
              entry.value.type,
              entry.value.timestamp),
      },
    );
  }
}

abstract class LocalLibraryBackupStorage {
  LocalLibrarySnapshot read();

  Future<T> runExclusive<T>(Future<T> Function() action);

  /// Called under runExclusive, including recovery after a failed replacement.
  Future<void> replace(LocalLibrarySnapshot snapshot);
}

class HiveLocalLibraryBackupStorage implements LocalLibraryBackupStorage {
  @override
  LocalLibrarySnapshot read() => LocalLibrarySnapshot(
        collections: GStorage.collectibles.toMap(),
        histories: GStorage.histories.toMap(),
        changes: GStorage.collectChanges.toMap(),
      ).detached();

  @override
  Future<T> runExclusive<T>(Future<T> Function() action) =>
      GStorage.runLibraryWriteExclusive(action);

  @override
  Future<void> replace(LocalLibrarySnapshot snapshot) async {
    // Keep the old values until putAll succeeds. The service rolls back all
    // three boxes on any write/delete/flush failure while holding the lock.
    await GStorage.collectibles.putAll(snapshot.collections);
    await GStorage.collectibles.deleteAll(GStorage.collectibles.keys
        .where((key) => !snapshot.collections.containsKey(key))
        .toList());
    await GStorage.collectibles.flush();
    await GStorage.histories.putAll(snapshot.histories);
    await GStorage.histories.deleteAll(GStorage.histories.keys
        .where((key) => !snapshot.histories.containsKey(key))
        .toList());
    await GStorage.histories.flush();
    await GStorage.collectChanges.putAll(snapshot.changes);
    await GStorage.collectChanges.deleteAll(GStorage.collectChanges.keys
        .where((key) => !snapshot.changes.containsKey(key))
        .toList());
    await GStorage.collectChanges.flush();
  }
}

class LocalLibraryArchive {
  const LocalLibraryArchive({
    required this.collections,
    required this.histories,
    required this.createdAt,
  });

  final List<CollectedBangumi> collections;
  final List<History> histories;
  final DateTime createdAt;
}

class LocalLibraryArchiveCodec {
  static const format = 'KazumiFlutter-library';
  static const version = 1;
  static const maxChars = 4000000;
  static const maxBytes = maxChars * 4;
  // Flutter has no native TV library's 200/100 record cap. Never truncate.
  static const maxRecords = 10000;

  static Uint8List encode(LocalLibraryArchive archive) {
    final raw = jsonEncode({
      'format': format,
      'version': version,
      'createdAt': archive.createdAt.millisecondsSinceEpoch,
      'collections': archive.collections.map(collectionJson).toList(),
      'history': archive.histories.map(HistorySyncCodec.historyToJson).toList(),
    });
    final bytes = Uint8List.fromList(utf8.encode(raw));
    decode(bytes); // Validate exported data as strictly as imported data.
    return bytes;
  }

  static LocalLibraryArchive decode(List<int> bytes) {
    if (bytes.length > maxBytes) _fail('tooLarge', '备份超过大小限制。');
    try {
      var raw = utf8.decode(bytes, allowMalformed: false);
      if (raw.length > maxChars) _fail('tooLarge', '备份超过大小限制。');
      if (raw.startsWith('\uFEFF')) raw = raw.substring(1);
      final root = _map(jsonDecode(raw));
      if (root['format'] != format ||
          root['version'] is! int ||
          root['version'] != version) {
        _fail('version', '不支持此备份格式或版本，请选择 Flutter 收藏与历史备份。');
      }
      final createdAt = _date(root['createdAt']);
      final collections = _list(root['collections']).map(collection).toList();
      final histories = _list(root['history']).map(history).toList();
      if (collections.length > maxRecords || histories.length > maxRecords) {
        _fail('tooLarge', '备份记录数量超过限制。');
      }
      if (collections.map((item) => item.bangumiItem.id).toSet().length !=
              collections.length ||
          histories.map((item) => item.key).toSet().length !=
              histories.length) {
        _fail('invalid', '备份存在重复记录，已停止恢复。');
      }
      return LocalLibraryArchive(
          collections: collections, histories: histories, createdAt: createdAt);
    } on LocalLibraryBackupException {
      rethrow;
    } catch (_) {
      _fail('invalid', '备份无法读取，请检查 UTF-8 编码和文件内容。');
    }
  }

  static Map<String, dynamic> collectionJson(CollectedBangumi value) => {
        'bangumiItem': HistorySyncCodec.bangumiItemToJson(value.bangumiItem),
        'time': value.time.millisecondsSinceEpoch,
        'type': value.type,
      };

  static CollectedBangumi collection(dynamic value) {
    final row = _map(value);
    final type = _integer(row['type'], min: 1, max: 5);
    _validateBangumi(row['bangumiItem']);
    return CollectedBangumi(
        HistorySyncCodec.bangumiItemFromJson(_map(row['bangumiItem'])),
        _date(row['time']),
        type);
  }

  static History history(dynamic value) {
    final row = _map(value);
    _validateBangumi(row['bangumiItem']);
    _integer(row['lastWatchEpisode'], min: 1);
    if (_string(row['adapterName']).isEmpty) _fail('invalid', '历史来源缺失。');
    _date(row['lastWatchTime']);
    _string(row['lastSrc']);
    _string(row['lastWatchEpisodeName']);
    _string(row['episodePageUrl']);
    if (row['entryKind'] != HistoryEntryKind.online &&
        row['entryKind'] != HistoryEntryKind.offline) {
      _fail('invalid', '历史记录类型无效。');
    }
    final progresses = _map(row['progresses']);
    if (progresses.length > maxRecords) _fail('tooLarge', '历史进度数量超过限制。');
    for (final entry in progresses.entries) {
      final progress = _map(entry.value);
      final episode = _integer(progress['episode'], min: 1);
      if (entry.key != episode.toString()) _fail('invalid', '历史进度键不匹配。');
      _integer(progress['road'], min: 0);
      _integer(progress['progressMs'], min: 0);
      _date(progress['updatedAtMs']);
    }
    return HistorySyncCodec.historyFromJson(row);
  }

  static void _validateBangumi(dynamic value) {
    final item = _map(value);
    _integer(item['id'], min: 1);
    _integer(item['type'], min: 1);
    for (final key in ['name', 'nameCn', 'summary', 'airDate', 'info']) {
      _string(item[key]);
    }
    _integer(item['airWeekday'], min: 0, max: 7);
    _integer(item['rank'], min: 0);
    final score = item['ratingScore'];
    if (score is! num || !score.isFinite || score < 0 || score > 10) {
      _fail('invalid', '番剧评分无效。');
    }
    _integer(item['votes'], min: 0);
    for (final count in _list(item['votesCount'])) {
      _integer(count, min: 0);
    }
    for (final alias in _list(item['alias'])) {
      _string(alias);
    }
    for (final image in _map(item['images']).values) {
      _string(image);
    }
    for (final tag in _list(item['tags'])) {
      final row = _map(tag);
      _string(row['name']);
      _integer(row['count'], min: 0);
      _integer(row['total_cont'], min: 0);
    }
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is! Map<String, dynamic>) _fail('invalid', '备份记录结构无效。');
    return value;
  }

  static List<dynamic> _list(dynamic value) {
    if (value is! List) _fail('invalid', '备份记录列表无效。');
    return value;
  }

  static String _string(dynamic value) {
    if (value is! String) _fail('invalid', '备份文本字段无效。');
    return value;
  }

  static int _integer(dynamic value, {int min = 0, int? max}) {
    if (value is! int || value < min || (max != null && value > max)) {
      _fail('invalid', '备份数字字段无效。');
    }
    return value;
  }

  static DateTime _date(dynamic value) => DateTime.fromMillisecondsSinceEpoch(
      _integer(value, max: 8640000000000000));

  static Never _fail(String code, String message) =>
      throw LocalLibraryBackupException(code, message);
}

class LocalLibraryBackupPreview {
  LocalLibraryBackupPreview._(this._archive, this._expected, this._owner);

  final LocalLibraryArchive _archive;
  final String _expected;
  final Object _owner;
  bool _active = true;

  int get collectionCount => _archive.collections.length;
  int get historyCount => _archive.histories.length;
  DateTime get createdAt => _archive.createdAt;
  List<String> get collectionSamples => _archive.collections.take(3).map((row) {
        final name = row.bangumiItem.nameCn.isEmpty
            ? row.bangumiItem.name
            : row.bangumiItem.nameCn;
        return '${['', '在看', '想看', '搁置', '看过', '抛弃'][row.type]} · $name';
      }).toList();
  List<String> get historySamples => _archive.histories.take(3).map((row) {
        final name = row.bangumiItem.nameCn.isEmpty
            ? row.bangumiItem.name
            : row.bangumiItem.nameCn;
        return '$name · ${row.lastWatchEpisodeName.isEmpty ? '第${row.lastWatchEpisode}集' : row.lastWatchEpisodeName}';
      }).toList();
}

class LocalLibraryBackupReadCancellation {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }

  void check() {
    if (isCancelled) {
      throw const LocalLibraryBackupException('cancelled', '已取消读取，收藏与历史未改动。');
    }
  }
}

class LocalLibraryBackupFile {
  const LocalLibraryBackupFile(this.name, this.createdAt);

  final String name;
  final DateTime createdAt;
}

class LocalLibraryBackupService {
  LocalLibraryBackupService({
    LocalLibraryBackupStorage? storage,
    Future<Directory> Function()? directory,
    DateTime Function()? now,
  })  : _storage = storage ?? HiveLocalLibraryBackupStorage(),
        _directory = directory ?? _defaultDirectory,
        _now = now ?? DateTime.now;

  final LocalLibraryBackupStorage _storage;
  final Future<Directory> Function() _directory;
  final DateTime Function() _now;
  final AsyncSerialQueue _operations = AsyncSerialQueue();
  final Object _owner = Object();
  LocalLibrarySnapshot? _undoBefore;
  String? _undoAfter;

  bool get canUndo => _undoBefore != null;

  void forgetUndo() {
    _undoBefore = null;
    _undoAfter = null;
  }

  static Future<Directory> _defaultDirectory() async => Directory(path.join(
      (await getApplicationSupportDirectory()).path, 'library-backups'));

  Future<Uint8List> export() =>
      _operations.run(() => _storage.runExclusive(() async {
            final snapshot = _storage.read();
            return LocalLibraryArchiveCodec.encode(LocalLibraryArchive(
                collections: snapshot.collections.values.toList(),
                histories: snapshot.histories.values.toList(),
                createdAt: _now()));
          }));

  Future<LocalLibraryBackupPreview> preview(List<int> bytes) async {
    final archive = LocalLibraryArchiveCodec.decode(bytes);
    return _operations.run(() => _storage.runExclusive(() async =>
        LocalLibraryBackupPreview._(
            archive, _storage.read().fingerprint, _owner)));
  }

  void cancelPreview(LocalLibraryBackupPreview preview) {
    if (identical(preview._owner, _owner)) preview._active = false;
  }

  Future<LocalLibraryBackupPreview> previewStream(Stream<List<int>> stream,
      {LocalLibraryBackupReadCancellation? cancellation}) async {
    final cancel = cancellation ?? LocalLibraryBackupReadCancellation();
    cancel.check();
    final bytes = BytesBuilder();
    final completed = Completer<Uint8List>();
    void fail(Object error, [StackTrace? stackTrace]) {
      if (!completed.isCompleted) completed.completeError(error, stackTrace);
    }

    // A single cancellation listener per transfer. Attaching one per chunk
    // retains all those pending listeners for providers yielding tiny chunks.
    cancel._cancelled.future.then((_) => fail(
        const LocalLibraryBackupException('cancelled', '已取消读取，收藏与历史未改动。')));
    final subscription = stream.listen(
        (chunk) {
          if (completed.isCompleted) return;
          if (bytes.length + chunk.length > LocalLibraryArchiveCodec.maxBytes) {
            fail(const LocalLibraryBackupException('tooLarge', '备份超过大小限制。'));
            return;
          }
          bytes.add(chunk);
        },
        onError: fail,
        onDone: () {
          if (!completed.isCompleted) completed.complete(bytes.takeBytes());
        },
        cancelOnError: true);
    try {
      final content = await completed.future;
      cancel.check();
      final result = await preview(content);
      if (cancel.isCancelled) {
        cancelPreview(result);
        cancel.check();
      }
      return result;
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> confirm(LocalLibraryBackupPreview preview) =>
      _operations.run(() => _storage.runExclusive(() async {
            if (!identical(preview._owner, _owner) || !preview._active) {
              throw const LocalLibraryBackupException(
                  'expired', '预览已取消或失效，请重新预览。');
            }
            final before = _storage.read();
            if (before.fingerprint != preview._expected) {
              preview._active = false;
              throw const LocalLibraryBackupException(
                  'changed', '预览后本地数据有变化，已阻止覆盖，请重新预览。');
            }
            final target = LocalLibrarySnapshot(
              collections: {
                for (final row in preview._archive.collections)
                  row.bangumiItem.id: row,
              },
              histories: {
                for (final row in preview._archive.histories) row.key: row,
              },
              changes: before.changes,
            );
            final updated = _withCollectionChanges(before, target);
            await _replaceOrRollback(before, updated);
            _undoBefore = before;
            _undoAfter = _storage.read().fingerprint;
            preview._active = false;
          }));

  Future<void> undo() => _operations.run(() => _storage.runExclusive(() async {
        final before = _undoBefore;
        if (before == null) {
          throw const LocalLibraryBackupException('noUndo', '没有可撤销的恢复。');
        }
        final current = _storage.read();
        if (current.fingerprint != _undoAfter) {
          throw const LocalLibraryBackupException(
              'changed', '恢复后已有新记录，已阻止撤销覆盖新数据。');
        }
        await _replaceOrRollback(
            current, _withCollectionChanges(current, before));
        forgetUndo();
      }));

  Future<void> _replaceOrRollback(
      LocalLibrarySnapshot before, LocalLibrarySnapshot target) async {
    try {
      await _storage.replace(target.detached());
    } catch (_) {
      try {
        await _storage.replace(before.detached());
      } catch (_) {
        throw const LocalLibraryBackupException(
            'rollbackFailed', '写入和回滚均失败，请保留备份文件，检查设备存储后重试。');
      }
      throw const LocalLibraryBackupException(
          'writeFailed', '恢复写入失败，已回滚原有收藏与历史。');
    }
  }

  LocalLibrarySnapshot _withCollectionChanges(
      LocalLibrarySnapshot current, LocalLibrarySnapshot target) {
    final journal = Map<dynamic, CollectedBangumiChange>.from(current.changes);
    final previous = {
      for (final row in current.collections.values) row.bangumiItem.id: row,
    };
    final next = {
      for (final row in target.collections.values) row.bangumiItem.id: row,
    };
    var id = max(_now().millisecondsSinceEpoch ~/ 1000,
        journal.values.fold<int>(0, (value, row) => max(value, row.id)) + 1);
    final timestamp = max(
        _now().millisecondsSinceEpoch ~/ 1000,
        journal.values.fold<int>(0, (value, row) => max(value, row.timestamp)) +
            1);
    final ids = {...previous.keys, ...next.keys}.toList()..sort();
    for (final bangumiId in ids) {
      final old = previous[bangumiId];
      final row = next[bangumiId];
      if (old != null &&
          row != null &&
          _canonicalJson(LocalLibraryArchiveCodec.collectionJson(old)) ==
              _canonicalJson(LocalLibraryArchiveCodec.collectionJson(row))) {
        continue;
      }
      while (journal.containsKey(id)) {
        id++;
      }
      if (id > 4294967295) {
        throw const LocalLibraryBackupException(
            'invalid', '收藏变更记录已超出容量，已停止恢复。');
      }
      journal[id] = CollectedBangumiChange(
          id,
          bangumiId,
          row == null
              ? 3
              : old == null
                  ? 1
                  : 2,
          row?.type ?? 5,
          timestamp);
      id++;
    }
    return LocalLibrarySnapshot(
        collections: target.collections,
        histories: target.histories,
        changes: journal);
  }

  Future<List<LocalLibraryBackupFile>> listLocal() async {
    final directory = await _directory();
    if (!await directory.exists()) return [];
    final files = <LocalLibraryBackupFile>[];
    await for (final file in directory.list(followLinks: false)) {
      if (file is! File) continue;
      final name = path.basename(file.path);
      final match = RegExp(r'^(\d+)-[a-f0-9]{16}\.json$').firstMatch(name);
      if (match == null) continue;
      final timestamp = int.tryParse(match.group(1)!);
      if (timestamp == null || timestamp > 8640000000000000) continue;
      files.add(LocalLibraryBackupFile(
          name, DateTime.fromMillisecondsSinceEpoch(timestamp)));
    }
    files.sort((a, b) {
      final date = b.createdAt.compareTo(a.createdAt);
      return date == 0 ? b.name.compareTo(a.name) : date;
    });
    return files;
  }

  Future<void> saveLocal() async {
    final bytes = await export();
    final directory = await _directory();
    await directory.create(recursive: true);
    final random = Random.secure();
    final suffix = List.generate(
        8, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final file = File(path.join(
        directory.path, '${_now().millisecondsSinceEpoch}-$suffix.json'));
    final pending = File('${file.path}.tmp');
    try {
      await pending.writeAsBytes(bytes, flush: true);
      await pending.rename(file.path);
    } finally {
      if (await pending.exists()) await pending.delete();
    }
    for (final old in (await listLocal()).skip(5)) {
      await File(path.join(directory.path, old.name)).delete();
    }
  }

  Future<LocalLibraryBackupPreview> previewLocal(LocalLibraryBackupFile file,
      {LocalLibraryBackupReadCancellation? cancellation}) async {
    final directory = await _directory();
    if (!(await listLocal()).any((row) => row.name == file.name)) {
      throw const LocalLibraryBackupException('missing', '此本地备份已不存在，请刷新列表。');
    }
    final source = File(path.join(directory.path, file.name));
    final canonicalDirectory = await directory.resolveSymbolicLinks();
    final canonicalSource = await source.resolveSymbolicLinks();
    if (path.dirname(canonicalSource) != canonicalDirectory) {
      throw const LocalLibraryBackupException('invalid', '本地备份路径无效。');
    }
    if (await source.length() > LocalLibraryArchiveCodec.maxBytes) {
      throw const LocalLibraryBackupException('tooLarge', '备份超过大小限制。');
    }
    return previewStream(source.openRead(), cancellation: cancellation);
  }
}

String _canonicalJson(dynamic value) {
  dynamic sort(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key as String).toList()..sort();
      return {for (final key in keys) key: sort(value[key])};
    }
    if (value is List) return value.map(sort).toList();
    return value;
  }

  return jsonEncode(sort(value));
}
