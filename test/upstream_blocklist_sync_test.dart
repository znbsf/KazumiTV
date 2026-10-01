import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/danmaku/danmaku_shield_sync.dart';
import 'package:kazumi/repositories/danmaku_shield_repository.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/sync/danmaku_shield_sync_service.dart';
import 'package:kazumi/services/sync/webdav.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

void main() {
  final webDav = WebDav();
  late Directory directory;
  late PathProviderPlatform originalPaths;

  setUpAll(() async {
    Logger.level = Level.off;
    directory = await Directory.systemTemp.createTemp('kazumi_blocklist_test_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });

  setUp(() async {
    await GStorage.resetSettings(SettingsKeys.byGroup(SettingGroup.webdav));
    await GStorage.resetSettings([
      SettingsKeys.danmakuShieldSyncDeviceId,
      SettingsKeys.danmakuShieldSyncState,
      SettingsKeys.danmakuShieldSyncCorruptState,
    ]);
    await GStorage.shieldList.clear();
    webDav.initialized = false;
  });

  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    expect(
        directory.absolute.path.startsWith(Directory.systemTemp.absolute.path),
        isTrue);
    expect(directory.uri.pathSegments.where((part) => part.isNotEmpty).last,
        startsWith('kazumi_blocklist_test_'));
    await directory.delete(recursive: true);
  });

  test('disabling WebDAV clears all dependent flags', () async {
    await GStorage.putSetting(SettingsKeys.webDavEnable, true);
    await GStorage.putSetting(SettingsKeys.webDavEnableHistory, true);
    await GStorage.putSetting(SettingsKeys.webDavEnableCollect, true);
    await GStorage.putSetting(SettingsKeys.webDavEnableDanmakuShield, true);

    await webDav.setEnabled(false);

    expect(GStorage.getSetting(SettingsKeys.webDavEnable), isFalse);
    expect(GStorage.getSetting(SettingsKeys.webDavEnableHistory), isFalse);
    expect(GStorage.getSetting(SettingsKeys.webDavEnableCollect), isFalse);
    expect(
        GStorage.getSetting(SettingsKeys.webDavEnableDanmakuShield), isFalse);
  });

  test('failed WebDAV initialization clears the previous connection', () async {
    webDav.initialized = true;

    await expectLater(webDav.init(), throwsException);

    expect(webDav.initialized, isFalse);
    await expectLater(webDav.setEnabled(true), throwsException);
    expect(GStorage.getSetting(SettingsKeys.webDavEnable), isFalse);
  });

  group('upstream blocklist WebDAV sync', () {
    late DanmakuShieldRepository repository;
    late DanmakuShieldSyncService service;
    const deviceA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const deviceB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    const root = '/kazumiSync/danmakuShield';
    late _MemoryWebDavClient client;

    Future<void> switchDevice(String id, {String state = ''}) async {
      await GStorage.shieldList.clear();
      await GStorage.putSetting(SettingsKeys.danmakuShieldSyncDeviceId, id);
      await GStorage.putSetting(SettingsKeys.danmakuShieldSyncState, state);
      await repository.initialize();
    }

    DanmakuShieldSyncState uploaded(String id) =>
        DanmakuShieldSyncState.decode(client.files['$root/$id.json']!);

    setUp(() async {
      repository = DanmakuShieldRepository();
      service = DanmakuShieldSyncService(repository, webDav);
      client = _MemoryWebDavClient();
      webDav.client = client;
      webDav.initialized = true;
      webDav.webDavLocalTempDirectory =
          Directory('${directory.path}/webdavTemp');
      await GStorage.putSetting(SettingsKeys.webDavEnable, true);
      await GStorage.putSetting(SettingsKeys.webDavEnableDanmakuShield, true);
      await GStorage.putSetting(
          SettingsKeys.danmakuShieldSyncDeviceId, deviceA);
    });

    tearDown(() async {
      await service.dispose();
      await repository.dispose();
    });

    test(
        'uploads existing rules on first sync and imports them on a new device',
        () async {
      await GStorage.shieldList.putAll({'剧透': '剧透', '/广告+/': '/广告+/'});

      await service.sync();

      expect(uploaded(deviceA).rules, unorderedEquals(['剧透', '/广告+/']));
      expect(client.files.keys, ['$root/$deviceA.json']);
      await switchDevice(deviceB);
      await repository.setRule('引战', deleted: false);
      await service.sync();

      expect(
          GStorage.shieldList.values, unorderedEquals(['剧透', '/广告+/', '引战']));
      expect(uploaded(deviceB).rules, unorderedEquals(['剧透', '/广告+/', '引战']));
      expect(client.files.keys,
          unorderedEquals(['$root/$deviceA.json', '$root/$deviceB.json']));
      expect(await webDav.webDavLocalTempDirectory.list().toList(), isEmpty);
    });

    test('offline deletions propagate to stale devices and allow re-adding',
        () async {
      await repository.setRule('剧透', deleted: false);
      await service.sync();
      final stateA = GStorage.getSetting(SettingsKeys.danmakuShieldSyncState);
      await switchDevice(deviceB);
      await service.sync();

      await GStorage.putSetting(SettingsKeys.webDavEnableDanmakuShield, false);
      await repository.setRule('剧透', deleted: true);
      await service.syncIfEnabled();
      expect(uploaded(deviceB).rules, ['剧透']);
      await GStorage.putSetting(SettingsKeys.webDavEnableDanmakuShield, true);
      await service.sync();
      final stateB = GStorage.getSetting(SettingsKeys.danmakuShieldSyncState);

      await switchDevice(deviceA, state: stateA);
      await service.sync();
      expect(GStorage.shieldList.values, isEmpty);
      expect(uploaded(deviceA).entries['剧透']!.deleted, isTrue);

      await repository.setRule('剧透', deleted: false);
      await service.sync();
      await switchDevice(deviceB, state: stateB);
      await service.sync();
      expect(GStorage.shieldList.values, ['剧透']);
    });

    test('failed upload preserves local changes for retry', () async {
      await repository.setRule('广告', deleted: false);
      await service.sync();
      await repository.setRule('广告', deleted: true);
      client.failUpload = true;

      await expectLater(service.sync(), throwsStateError);

      expect(GStorage.shieldList.values, isEmpty);
      expect(uploaded(deviceA).rules, ['广告']);
      client.failUpload = false;
      await service.sync();
      expect(uploaded(deviceA).rules, isEmpty);
      expect(uploaded(deviceA).entries['广告']!.deleted, isTrue);
      expect(await webDav.webDavLocalTempDirectory.list().toList(), isEmpty);
    });

    test('invalid remote files never partially apply or overwrite data',
        () async {
      await repository.setRule('本地', deleted: false);
      final before = GStorage.getSetting(SettingsKeys.danmakuShieldSyncState);
      client.files['$root/$deviceA.json'] = DanmakuShieldSyncState([
        const DanmakuShieldSyncEntry(
            rule: '远端', updatedAt: 1, deviceId: deviceA, deleted: false),
      ]).encode();
      client.files['$root/$deviceB.json'] = '{invalid';
      final remoteBefore = Map.of(client.files);

      await expectLater(service.sync(), throwsFormatException);

      expect(GStorage.shieldList.values, ['本地']);
      expect(GStorage.getSetting(SettingsKeys.danmakuShieldSyncState), before);
      expect(client.files, remoteBefore);
      expect(await webDav.webDavLocalTempDirectory.list().toList(), isEmpty);
    });

    test('an edit during upload is included in the queued sync', () async {
      await repository.setRule('原有', deleted: false);
      final uploading = Completer<void>();
      final resume = Completer<void>();
      client.beforeUpload = () async {
        client.beforeUpload = null;
        uploading.complete();
        await resume.future;
      };
      final first = service.sync();
      await uploading.future;
      await repository.setRule('新增', deleted: false);
      await repository.setRule('原有', deleted: true);
      final second = service.sync();
      resume.complete();
      await Future.wait([first, second]);

      expect(uploaded(deviceA).rules, ['新增']);
      expect(uploaded(deviceA).entries['原有']!.deleted, isTrue);
      expect(GStorage.shieldList.values, ['新增']);
    });

    test('empty local and remote sets publish a valid empty device document',
        () async {
      await service.sync();
      expect(uploaded(deviceA).entries, isEmpty);
      expect(GStorage.shieldList.values, isEmpty);
      expect(client.files.keys, ['$root/$deviceA.json']);
    });

    test('failed final MOVE preserves the last published remote document',
        () async {
      await repository.setRule('广告', deleted: false);
      await service.sync();
      final published = client.files['$root/$deviceA.json'];
      await repository.setRule('广告', deleted: true);
      client.failRename = true;
      await expectLater(service.sync(), throwsStateError);
      expect(client.files['$root/$deviceA.json'], published);
      expect(GStorage.shieldList.values, isEmpty);
      expect(client.files.keys, ['$root/$deviceA.json']);
      client.failRename = false;
      await service.sync();
      expect(uploaded(deviceA).entries['广告']!.deleted, isTrue);
    });

    test('download failure preserves both local metadata and published files',
        () async {
      await repository.setRule('本地', deleted: false);
      client.files['$root/$deviceB.json'] = DanmakuShieldSyncState([
        const DanmakuShieldSyncEntry(
            rule: '远端', updatedAt: 1, deviceId: deviceB, deleted: false),
      ]).encode();
      final saved = GStorage.getSetting(SettingsKeys.danmakuShieldSyncState);
      final remote = Map.of(client.files);
      client.failDownload = true;
      await expectLater(service.sync(), throwsStateError);
      expect(repository.getRules(), ['本地']);
      expect(GStorage.getSetting(SettingsKeys.danmakuShieldSyncState), saved);
      expect(client.files, remote);
      expect(await webDav.webDavLocalTempDirectory.list().toList(), isEmpty);
    });

    test('disabled master or blocklist flag never touches the server',
        () async {
      await repository.setRule('本地', deleted: false);
      await GStorage.putSetting(SettingsKeys.webDavEnable, false);
      await service.sync();
      expect(client.files, isEmpty);
      await GStorage.putSetting(SettingsKeys.webDavEnable, true);
      await GStorage.putSetting(SettingsKeys.webDavEnableDanmakuShield, false);
      await service.sync();
      expect(client.files, isEmpty);
      expect(repository.getRules(), ['本地']);
    });

    test('unrelated names and unfinished cache files are not imported',
        () async {
      client.files['$root/notes.json'] = '{invalid';
      client.files['$root/$deviceB.json.cache'] = '{invalid';
      await repository.setRule('本地', deleted: false);
      await service.sync();
      expect(uploaded(deviceA).rules, ['本地']);
      expect(client.files['$root/notes.json'], '{invalid');
      expect(client.files['$root/$deviceB.json.cache'], '{invalid');
    });

    test('disabling blocklist during download prevents merge and upload',
        () async {
      await repository.setRule('本地', deleted: false);
      final before = GStorage.getSetting(SettingsKeys.danmakuShieldSyncState);
      client.files['$root/$deviceB.json'] = DanmakuShieldSyncState([
        const DanmakuShieldSyncEntry(
            rule: '远端', updatedAt: 1, deviceId: deviceB, deleted: false),
      ]).encode();
      final remote = Map.of(client.files);
      client.afterDownload = () =>
          GStorage.putSetting(SettingsKeys.webDavEnableDanmakuShield, false);
      await service.sync();
      expect(repository.getRules(), ['本地']);
      expect(GStorage.getSetting(SettingsKeys.danmakuShieldSyncState), before);
      expect(client.files, remote);
    });

    test('invalid device identity cannot become a remote path', () async {
      var merged = false;
      await expectLater(
          webDav.syncDanmakuShield(
              deviceId: '../invalid',
              merge: (state) async {
                merged = true;
                return state;
              }),
          throwsFormatException);
      expect(merged, isFalse);
      expect(client.files, isEmpty);
    });

    test('corrupt sync metadata does not prevent offline edits or restart',
        () async {
      const corrupt = '{"version":1,"entries":[';
      await GStorage.putSetting(SettingsKeys.webDavEnable, false);
      await GStorage.shieldList.put('旧规则', '旧规则');
      await GStorage.putSetting(SettingsKeys.danmakuShieldSyncState, corrupt);

      await repository.setRule('/广告+/', deleted: false);
      await repository.setRule('旧规则', deleted: true);
      expect(repository.getRules(), ['/广告+/']);
      expect(GStorage.getSetting(SettingsKeys.danmakuShieldSyncCorruptState),
          corrupt);

      final restarted = DanmakuShieldRepository();
      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(restarted.getRules(), ['/广告+/']);
      final saved = DanmakuShieldSyncState.decode(
          GStorage.getSetting(SettingsKeys.danmakuShieldSyncState));
      expect(saved.entries['旧规则']!.deleted, isTrue);
    });
  });

  group('blocklist persistence and conflict contract', () {
    late Box<String> rules;
    late Box<String> settings;
    late DanmakuShieldRepository repository;
    const device = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    setUp(() async {
      rules = await Hive.openBox<String>('blocklist_rules');
      settings = await Hive.openBox<String>('blocklist_metadata');
      await rules.clear();
      await settings.clear();
      await settings.put(SettingsKeys.danmakuShieldSyncDeviceId.name, device);
      repository = DanmakuShieldRepository(
          rulesBox: rules,
          readSetting: (key) => settings.get(key.name) ?? key.defaultValue,
          writeSetting: (key, value) => settings.put(key.name, value),
          nowMilliseconds: () => 10);
    });
    tearDown(() async {
      await repository.dispose();
      if (rules.isOpen) await rules.close();
      if (settings.isOpen) await settings.close();
    });

    test('local rules and tombstones survive closing both Hive boxes',
        () async {
      await repository.setRule('旧规则', deleted: false);
      await repository.setRule('/广告+/', deleted: false);
      await repository.setRule('旧规则', deleted: true);
      await repository.dispose();
      await rules.close();
      await settings.close();
      rules = await Hive.openBox<String>('blocklist_rules');
      settings = await Hive.openBox<String>('blocklist_metadata');
      repository = DanmakuShieldRepository(
          rulesBox: rules,
          readSetting: (key) => settings.get(key.name) ?? key.defaultValue,
          writeSetting: (key, value) => settings.put(key.name, value));
      await repository.initialize();
      expect(repository.getRules(), ['/广告+/']);
      final saved = DanmakuShieldSyncState.decode(
          settings.get(SettingsKeys.danmakuShieldSyncState.name)!);
      expect(saved.entries['旧规则']!.deleted, isTrue);
      expect(await repository.getDeviceId(), device);
    });

    test('metadata write failure preserves projection and permits retry',
        () async {
      var fail = true;
      final failing = DanmakuShieldRepository(
          rulesBox: rules,
          readSetting: (key) => settings.get(key.name) ?? key.defaultValue,
          writeSetting: (key, value) async {
            if (key == SettingsKeys.danmakuShieldSyncState && fail) {
              fail = false;
              throw StateError('metadata unavailable');
            }
            await settings.put(key.name, value);
          });
      addTearDown(failing.dispose);
      await expectLater(
          failing.setRule('广告', deleted: false), throwsStateError);
      expect(rules.values, isEmpty);
      expect(settings.get(SettingsKeys.danmakuShieldSyncState.name), isNull);
      expect(await failing.setRule('广告', deleted: false), isTrue);
      expect(rules.values, ['广告']);
    });

    test('committed metadata repairs an interrupted Hive projection', () async {
      final failing = DanmakuShieldRepository(
          rulesBox: _FailingProjectionBox(rules),
          readSetting: (key) => settings.get(key.name) ?? key.defaultValue,
          writeSetting: (key, value) => settings.put(key.name, value));
      addTearDown(failing.dispose);
      await expectLater(
          failing.setRule('广告', deleted: false), throwsStateError);
      expect(rules.values, isEmpty);
      expect(
          DanmakuShieldSyncState.decode(
                  settings.get(SettingsKeys.danmakuShieldSyncState.name)!)
              .rules,
          ['广告']);
      await repository.initialize();
      expect(repository.getRules(), ['广告']);
    });

    test('clock rollback still creates a newer local edit after remote merge',
        () async {
      await repository.mergeSyncState(DanmakuShieldSyncState([
        const DanmakuShieldSyncEntry(
            rule: '广告',
            updatedAt: 900,
            deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            deleted: false),
      ]));
      await repository.setRule('广告', deleted: true);
      final saved = DanmakuShieldSyncState.decode(
          settings.get(SettingsKeys.danmakuShieldSyncState.name)!);
      expect(saved.entries['广告']!.updatedAt, 901);
      expect(saved.entries['广告']!.deleted, isTrue);
    });

    test('equal timestamps converge independent of merge direction', () {
      final a = DanmakuShieldSyncState([
        const DanmakuShieldSyncEntry(
            rule: '广告', updatedAt: 7, deviceId: 'a', deleted: true),
      ]);
      final b = DanmakuShieldSyncState([
        const DanmakuShieldSyncEntry(
            rule: '广告', updatedAt: 7, deviceId: 'b', deleted: false),
      ]);
      expect(a.merge(b).encode(), b.merge(a).encode());
      expect(a.merge(b).entries['广告']!.deviceId, 'b');
    });

    test('same timestamp and device keeps deletion over stale addition', () {
      final added = DanmakuShieldSyncState([
        const DanmakuShieldSyncEntry(
            rule: '广告', updatedAt: 7, deviceId: device, deleted: false),
      ]);
      final removed = DanmakuShieldSyncState([
        const DanmakuShieldSyncEntry(
            rule: '广告', updatedAt: 7, deviceId: device, deleted: true),
      ]);
      expect(added.merge(removed).rules, isEmpty);
      expect(added.merge(removed).encode(), removed.merge(added).encode());
    });
  });
}

class _MemoryWebDavClient implements webdav.Client {
  final files = <String, String>{};
  bool failUpload = false;
  bool failRename = false;
  bool failDownload = false;
  Future<void> Function()? afterDownload;
  Future<void> Function()? beforeUpload;

  @override
  Future<void> mkdir(String path, [CancelToken? cancelToken]) async {}

  @override
  Future<List<webdav.File>> readDir(String path,
      [CancelToken? cancelToken]) async {
    return [
      for (final entry in files.entries)
        if (entry.key.startsWith('$path/'))
          webdav.File(
              name: entry.key.substring(path.length + 1),
              isDir: false,
              size: entry.value.length),
    ];
  }

  @override
  Future<void> read2File(String path, String savePath,
      {void Function(int, int)? onProgress, CancelToken? cancelToken}) async {
    if (failDownload) throw StateError('Download failed');
    final contents = files[path];
    if (contents == null) throw StateError('File missing: $path');
    await File(savePath).writeAsString(contents);
    await afterDownload?.call();
  }

  @override
  Future<void> writeFromFile(String localFilePath, String path,
      {void Function(int, int)? onProgress, CancelToken? cancelToken}) async {
    await beforeUpload?.call();
    if (failUpload) throw StateError('Upload failed');
    files[path] = await File(localFilePath).readAsString();
  }

  @override
  Future<void> remove(String path, [CancelToken? cancelToken]) async {
    files.remove(path);
  }

  @override
  Future<void> rename(String oldPath, String newPath, bool overwrite,
      [CancelToken? cancelToken]) async {
    if (failRename) throw StateError('MOVE failed');
    files[newPath] = files.remove(oldPath)!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _FailingProjectionBox implements Box<String> {
  _FailingProjectionBox(this.delegate);
  final Box<String> delegate;
  bool fail = true;
  @override
  Iterable<dynamic> get keys => delegate.keys;
  @override
  Iterable<String> get values => delegate.values;
  @override
  String? get(dynamic key, {String? defaultValue}) =>
      delegate.get(key, defaultValue: defaultValue);
  @override
  bool containsKey(dynamic key) => delegate.containsKey(key);
  @override
  Future<void> deleteAll(Iterable<dynamic> keys) async {
    if (fail) {
      fail = false;
      throw StateError('projection unavailable');
    }
    await delegate.deleteAll(keys);
  }

  @override
  Future<void> putAll(Map<dynamic, String> entries) => delegate.putAll(entries);
  @override
  Future<void> flush() => delegate.flush();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
