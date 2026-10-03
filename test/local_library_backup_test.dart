import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/hive_registrar.g.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/bangumi_tag.dart';
import 'package:kazumi/modules/collect/collect_change_module.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/services/storage/local_library_backup.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/async_serial_queue.dart';

void main() {
  late _MemoryStorage storage;
  late LocalLibraryBackupService service;

  setUp(() {
    storage = _MemoryStorage(_snapshot(1));
    service = LocalLibraryBackupService(
        storage: storage,
        now: () => DateTime.fromMillisecondsSinceEpoch(2000000000000));
  });

  group('versioned archive validation', () {
    test('round trips full persisted schema including all episode progress',
        () {
      final original = _snapshot(1);
      final archive = LocalLibraryArchiveCodec.decode(_archive(original));
      final roundTrip = LocalLibrarySnapshot(
          collections: {1: archive.collections.single},
          histories: {'legacy-key': archive.histories.single},
          changes: original.changes);
      expect(roundTrip.fingerprint, original.fingerprint);
      expect(archive.histories.single.progresses.keys, [1, 2]);
      expect(archive.histories.single.progresses[2]!.updatedAtMs, 4000);
      expect(archive.histories.single.episodePageUrl,
          'https://fixture.invalid/episode');
      expect(archive.histories.single.bangumiItem.tags.single.totalCount, 3);
    });

    test('accepts a UTF-8 BOM and Chinese text', () {
      final bytes = [0xef, 0xbb, 0xbf, ..._archive(_snapshot(1))];
      expect(
          LocalLibraryArchiveCodec.decode(bytes)
              .collections
              .single
              .bangumiItem
              .nameCn,
          '测试番剧 1');
    });

    for (final entry in <String, void Function(Map<String, dynamic>)>{
      'future version': (json) => json['version'] = 2,
      'fractional version': (json) => json['version'] = 1.0,
      'foreign format': (json) => json['format'] = 'KazumiTV-library',
      'missing collection list': (json) => json.remove('collections'),
      'duplicate collection': (json) =>
          (json['collections'] as List).add(json['collections'][0]),
      'duplicate history identity': (json) =>
          (json['history'] as List).add(json['history'][0]),
      'invalid collection type': (json) => json['collections'][0]['type'] = 0,
      'invalid date': (json) => json['createdAt'] = -1,
      'invalid record text': (json) =>
          json['collections'][0]['bangumiItem']['name'] = 12,
      'invalid origin kind': (json) =>
          json['history'][0]['entryKind'] = 'future',
      'invalid progress': (json) =>
          json['history'][0]['progresses']['1']['progressMs'] = -1,
      'fractional progress': (json) =>
          json['history'][0]['progresses']['1']['progressMs'] = 0.5,
      'mismatched progress identity': (json) =>
          json['history'][0]['progresses']['1']['episode'] = 2,
    }.entries) {
      test('${entry.key} is rejected without a business write', () async {
        final json = _json(_archive(_snapshot(2)));
        entry.value(json);
        final before = storage.read().fingerprint;
        await expectLater(service.preview(utf8.encode(jsonEncode(json))),
            throwsA(isA<LocalLibraryBackupException>()));
        expect(storage.writes, 0);
        expect(storage.read().fingerprint, before);
      });
    }

    test('malformed JSON and UTF-8 have zero writes', () async {
      for (final bytes in [
        utf8.encode('{bad'),
        [0xc3, 0x28]
      ]) {
        await expectLater(service.preview(bytes), throwsA(_failure('invalid')));
      }
      expect(storage.writes, 0);
    });

    test('oversized character payload has zero writes', () async {
      final bytes = utf8.encode(' ' * (LocalLibraryArchiveCodec.maxChars + 1));
      await expectLater(service.preview(bytes), throwsA(_failure('tooLarge')));
      expect(storage.writes, 0);
    });

    test('invalid local records cannot produce a misleading export', () async {
      storage.snapshot.histories.values.single.progresses[1]!.progress =
          const Duration(milliseconds: -1);
      await expectLater(service.export(), throwsA(_failure('invalid')));
      expect(storage.writes, 0);
    });
  });

  group('preview, confirmation and undo', () {
    test('preview exposes counts and samples without writing', () async {
      final preview = await service.preview(_archive(_snapshot(2)));
      expect(preview.collectionCount, 1);
      expect(preview.historyCount, 1);
      expect(preview.collectionSamples, ['想看 · 测试番剧 2']);
      expect(preview.historySamples, ['测试番剧 2 · 第二集']);
      expect(storage.writes, 0);
    });

    test('cancel and an expired preview cannot write', () async {
      final preview = await service.preview(_archive(_snapshot(2)));
      service.cancelPreview(preview);
      await expectLater(service.confirm(preview), throwsA(_failure('expired')));
      expect(storage.writes, 0);
      expect(service.canUndo, isFalse);
    });

    test('a preview from another service cannot authorize a write', () async {
      final preview = await service.preview(_archive(_snapshot(2)));
      final other = LocalLibraryBackupService(storage: storage);
      await expectLater(other.confirm(preview), throwsA(_failure('expired')));
      expect(storage.writes, 0);
    });

    test('a progress mutation after preview rejects replacement', () async {
      final preview = await service.preview(_archive(_snapshot(2)));
      storage.snapshot.histories.values.single.progresses[1]!.progress =
          const Duration(milliseconds: 99999);
      final newer = storage.read().fingerprint;
      await expectLater(service.confirm(preview), throwsA(_failure('changed')));
      expect(storage.writes, 0);
      expect(storage.read().fingerprint, newer);
    });

    test('journal changes after preview are included in the guard', () async {
      final preview = await service.preview(_archive(_snapshot(2)));
      storage.snapshot.changes[99] = CollectedBangumiChange(99, 1, 2, 4, 99);
      await expectLater(service.confirm(preview), throwsA(_failure('changed')));
      expect(storage.writes, 0);
    });

    test('confirmation checks after queued business writes acquire the lock',
        () async {
      final preview = await service.preview(_archive(_snapshot(2)));
      final entered = Completer<void>();
      final release = Completer<void>();
      final queued = storage.runExclusive(() async {
        entered.complete();
        await release.future;
        storage.snapshot.histories['new'] = _history(3);
      });
      await entered.future;
      final confirmation = service.confirm(preview);
      final assertion = expectLater(confirmation, throwsA(_failure('changed')));
      release.complete();
      await queued;
      await assertion;
      expect(storage.writes, 0);
      expect(storage.snapshot.histories.containsKey('new'), isTrue);
    });

    test('restore and one undo preserve schema, original keys and sync journal',
        () async {
      final before = storage.read();
      final preview = await service.preview(_archive(_snapshot(2)));
      await service.confirm(preview);
      expect(storage.snapshot.collections.keys, [2]);
      expect(storage.snapshot.histories.keys, [_history(2).key]);
      expect(
          storage.snapshot.changes.values.map((row) => row.action), [1, 3, 1]);
      expect(service.canUndo, isTrue);
      await expectLater(service.confirm(preview), throwsA(_failure('expired')));
      await service.undo();
      final restored = storage.read();
      expect(restored.collections.keys, before.collections.keys);
      expect(restored.histories.keys, ['legacy-key']);
      expect(
          restored
              .histories.values.single.progresses[2]!.progress.inMilliseconds,
          4500);
      expect(restored.changes.length, 5);
      expect(restored.changes.values.last.action, 3);
      expect(service.canUndo, isFalse);
      await expectLater(service.undo(), throwsA(_failure('noUndo')));
    });

    test('undo rejects new history and does not overwrite it', () async {
      await service.confirm(await service.preview(_archive(_snapshot(2))));
      storage.snapshot.histories['new-record'] = _history(3);
      final afterNewRecord = storage.read().fingerprint;
      final writes = storage.writes;
      await expectLater(service.undo(), throwsA(_failure('changed')));
      expect(storage.read().fingerprint, afterNewRecord);
      expect(storage.writes, writes);
    });

    test('replacement failure rolls back every box and original keys',
        () async {
      final before = storage.read().fingerprint;
      final preview = await service.preview(_archive(_snapshot(2)));
      storage.failNextWrite = true;
      await expectLater(
          service.confirm(preview), throwsA(_failure('writeFailed')));
      expect(storage.read().fingerprint, before);
      expect(storage.writes, 2);
      expect(service.canUndo, isFalse);
    });

    test('failed undo rolls back imported data and remains retryable',
        () async {
      await service.confirm(await service.preview(_archive(_snapshot(2))));
      final imported = storage.read().fingerprint;
      storage.failNextWrite = true;
      await expectLater(service.undo(), throwsA(_failure('writeFailed')));
      expect(storage.read().fingerprint, imported);
      expect(service.canUndo, isTrue);
      await service.undo();
      expect(storage.snapshot.collections.keys, [1]);
    });

    test('rollback failure is reported explicitly', () async {
      final preview = await service.preview(_archive(_snapshot(2)));
      storage.failEveryWrite = true;
      await expectLater(
          service.confirm(preview), throwsA(_failure('rollbackFailed')));
      expect(service.canUndo, isFalse);
    });

    test('leaving the page can clear the only undo snapshot', () async {
      await service.confirm(await service.preview(_archive(_snapshot(2))));
      service.forgetUndo();
      expect(service.canUndo, isFalse);
      await expectLater(service.undo(), throwsA(_failure('noUndo')));
    });
  });

  group('bounded cancellable reading and local files', () {
    test('cancellation before reading performs zero writes', () async {
      final cancellation = LocalLibraryBackupReadCancellation()..cancel();
      await expectLater(
          service.previewStream(Stream.value(_archive(_snapshot(2))),
              cancellation: cancellation),
          throwsA(_failure('cancelled')));
      expect(storage.writes, 0);
    });

    test('cancel interrupts a stalled provider stream and closes subscription',
        () async {
      final cancelled = Completer<void>();
      final stream = StreamController<List<int>>(onCancel: cancelled.complete);
      final cancellation = LocalLibraryBackupReadCancellation();
      final pending =
          service.previewStream(stream.stream, cancellation: cancellation);
      stream.add([123]);
      await Future<void>.delayed(Duration.zero);
      final assertion = expectLater(pending, throwsA(_failure('cancelled')));
      cancellation.cancel();
      await assertion;
      await cancelled.future;
      expect(storage.writes, 0);
      await stream.close();
    });

    test('provider read error performs zero writes', () async {
      await expectLater(
          service.previewStream(
              Stream.error(const FileSystemException('fixture'))),
          throwsA(isA<FileSystemException>()));
      expect(storage.writes, 0);
    });

    test('tiny provider chunks can be cancelled once without writing',
        () async {
      var closes = 0;
      final stream =
          StreamController<List<int>>(sync: true, onCancel: () => closes++);
      final cancellation = LocalLibraryBackupReadCancellation();
      final pending =
          service.previewStream(stream.stream, cancellation: cancellation);
      for (var i = 0; i < 10000; i++) {
        stream.add([32]);
      }
      final assertion = expectLater(pending, throwsA(_failure('cancelled')));
      cancellation.cancel();
      cancellation.cancel();
      await assertion;
      expect(closes, 1);
      expect(storage.writes, 0);
      await stream.close();
    });

    test('byte cap rejects before decoding or reading further', () async {
      final chunk = Uint8List(1000000);
      await expectLater(
          service.previewStream(
              Stream.fromIterable(List.generate(17, (_) => chunk))),
          throwsA(_failure('tooLarge')));
      expect(storage.writes, 0);
    });

    test('split UTF-8 sequences decode correctly across stream chunks',
        () async {
      final bytes = _archive(_snapshot(2));
      final chunks = [
        for (var i = 0; i < bytes.length; i++) [bytes[i]]
      ];
      final preview = await service.previewStream(Stream.fromIterable(chunks));
      expect(preview.collectionSamples.single, contains('测试番剧'));
      expect(storage.writes, 0);
    });

    test('local backups keep latest five; preview uses fixture files only',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('kazumi-backup-fixture-');
      var timestamp = 2000000000000;
      final files = LocalLibraryBackupService(
          storage: storage,
          directory: () async => directory,
          now: () => DateTime.fromMillisecondsSinceEpoch(timestamp++));
      try {
        for (var i = 0; i < 6; i++) {
          await files.saveLocal();
        }
        final backups = await files.listLocal();
        expect(backups, hasLength(5));
        expect(await directory.list().length, 5);
        expect(backups.first.createdAt.isAfter(backups.last.createdAt), isTrue);
        expect((await files.previewLocal(backups.first)).historyCount, 1);
        expect(storage.writes, 0);
        await expectLater(
            files.previewLocal(LocalLibraryBackupFile(
                '../escape.json', DateTime.fromMillisecondsSinceEpoch(0))),
            throwsA(_failure('missing')));
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('backup ordering uses timestamp across different digit lengths',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('kazumi-backup-date-fixture-');
      final files = LocalLibraryBackupService(
          storage: storage, directory: () async => directory);
      try {
        for (final name in [
          '9-aaaaaaaaaaaaaaaa.json',
          '10-bbbbbbbbbbbbbbbb.json',
        ]) {
          await File('${directory.path}/$name')
              .writeAsBytes(_archive(_snapshot(1)));
        }
        expect(
            (await files.listLocal())
                .map((row) => row.createdAt.millisecondsSinceEpoch),
            [10, 9]);
        expect(storage.writes, 0);
      } finally {
        await directory.delete(recursive: true);
      }
    });
  });

  test(
      'Hive integration restores the same business boxes with fixture data only',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('kazumi-backup-hive-fixture-');
    Hive.init(directory.path);
    Hive.registerAdapters();
    try {
      GStorage.collectibles =
          await Hive.openBox<CollectedBangumi>('fixture-collections');
      GStorage.histories = await Hive.openBox<History>('fixture-histories');
      GStorage.collectChanges =
          await Hive.openBox<CollectedBangumiChange>('fixture-changes');
      final initial = _snapshot(1);
      final hive = HiveLocalLibraryBackupStorage();
      await hive.runExclusive(() => hive.replace(initial));
      final backups = LocalLibraryBackupService(storage: hive);
      final preview = await backups.preview(_archive(_snapshot(2)));
      await backups.confirm(preview);
      expect(GStorage.collectibles.get(2)!.bangumiItem.nameCn, '测试番剧 2');
      expect(GStorage.histories.get(_history(2).key)!.progresses.keys, [1, 2]);
      await backups.undo();
      expect(GStorage.histories.containsKey('legacy-key'), isTrue);
      expect(GStorage.histories.get('legacy-key')!.entryKind,
          HistoryEntryKind.offline);
      final nextChange =
          await GStorage.appendCollectChange(bangumiId: 1, action: 2, type: 4);
      expect(nextChange.id, greaterThan(100));
      expect(GStorage.collectChanges.values.map((row) => row.id).toSet().length,
          GStorage.collectChanges.length);
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });
}

Matcher _failure(String code) => isA<LocalLibraryBackupException>()
    .having((error) => error.code, 'code', code);

Map<String, dynamic> _json(List<int> bytes) =>
    jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

Uint8List _archive(LocalLibrarySnapshot snapshot) =>
    LocalLibraryArchiveCodec.encode(LocalLibraryArchive(
        collections: snapshot.collections.values.toList(),
        histories: snapshot.histories.values.toList(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(5000)));

LocalLibrarySnapshot _snapshot(int id) => LocalLibrarySnapshot(collections: {
      id: CollectedBangumi(
          _item(id), DateTime.fromMillisecondsSinceEpoch(2000), 2)
    }, histories: {
      'legacy-key': _history(id)
    }, changes: {
      100: CollectedBangumiChange(100, id, 1, 2, 100)
    });

History _history(int id) {
  final history = History(
      _item(id),
      2,
      'fixture-provider',
      DateTime.fromMillisecondsSinceEpoch(5000),
      'https://fixture.invalid/title',
      '第二集',
      entryKind: HistoryEntryKind.offline,
      episodePageUrl: 'https://fixture.invalid/episode');
  history.progresses = {
    1: Progress(1, 0, 3500, updatedAtMs: 3000),
    2: Progress(2, 1, 4500, updatedAtMs: 4000),
  };
  return history;
}

BangumiItem _item(int id) => BangumiItem(
    id: id,
    type: 2,
    name: 'Fixture $id',
    nameCn: '测试番剧 $id',
    summary: 'fixture summary',
    airDate: '2026-01-01',
    airWeekday: 4,
    rank: 10,
    images: {'large': 'https://fixture.invalid/image'},
    tags: [BangumiTag(name: 'fixture', count: 2, totalCount: 3)],
    alias: ['fixture alias'],
    ratingScore: 8.5,
    votes: 5,
    votesCount: [1, 2, 3],
    info: 'fixture info');

class _MemoryStorage implements LocalLibraryBackupStorage {
  _MemoryStorage(this.snapshot);

  LocalLibrarySnapshot snapshot;
  int writes = 0;
  bool failNextWrite = false;
  bool failEveryWrite = false;
  final AsyncSerialQueue _queue = AsyncSerialQueue();

  @override
  LocalLibrarySnapshot read() => snapshot.detached();

  @override
  Future<T> runExclusive<T>(Future<T> Function() action) => _queue.run(action);

  @override
  Future<void> replace(LocalLibrarySnapshot replacement) async {
    writes++;
    if (failNextWrite || failEveryWrite) {
      failNextWrite = false;
      // Model failure after one box is replaced, before remaining boxes.
      snapshot = LocalLibrarySnapshot(
          collections: replacement.collections,
          histories: snapshot.histories,
          changes: snapshot.changes);
      throw const FileSystemException('fixture write failed');
    }
    snapshot = replacement.detached();
  }
}
