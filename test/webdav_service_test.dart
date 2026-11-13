import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:webdav_client/webdav_client.dart' as dav;
import 'package:kazumi/modules/collect/collect_change_module.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/sync/webdav.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  final webDav = WebDav();
  late Directory directory;
  late PathProviderPlatform originalPaths;

  setUpAll(() async {
    Logger.level = Level.off;
    directory = await Directory.systemTemp.createTemp('kazumi_webdav_test_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });

  setUp(() async {
    await GStorage.resetSettings(SettingsKeys.byGroup(SettingGroup.webdav));
    webDav.initialized = false;
  });

  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    expect(
        directory.absolute.path.startsWith(Directory.systemTemp.absolute.path),
        isTrue);
    expect(directory.uri.pathSegments.where((part) => part.isNotEmpty).last,
        startsWith('kazumi_webdav_test_'));
    await directory.delete(recursive: true);
  });

  test('device snapshots preserve both logs and import legacy shared boxes',
      () async {
    final client = _MemoryDav();
    webDav.client = client;
    webDav.initialized = true;
    webDav.webDavLocalTempDirectory = Directory('${directory.path}/webdav');
    // Legacy upload helper expects support/hive, as in production.
    await Directory('${directory.path}/hive').create();
    Future<void> copyBoxes() async {
      for (final box in [GStorage.collectibles, GStorage.collectChanges]) {
        await box.flush();
        await File(box.path!).copy('${directory.path}/hive/${box.name}.hive');
      }
    }

    await GStorage.putSetting(SettingsKeys.historySyncDeviceId, 'device-a');
    await GStorage.collectChanges
        .put(7, CollectedBangumiChange(7, 1, 3, 1, 10));
    await copyBoxes();
    await webDav.syncCollectibles();
    final first =
        client.files['/kazumiSync/collection-devices-v1/device-a.json'];
    expect(jsonDecode(first!)['version'], 1);
    await GStorage.collectChanges.clear();
    await GStorage.putSetting(SettingsKeys.historySyncDeviceId, 'device-b');
    await GStorage.collectChanges
        .put(7, CollectedBangumiChange(7, 2, 3, 1, 20));
    await copyBoxes();
    await webDav.syncCollectibles();
    expect(
        GStorage.collectChanges.values.map((c) => c.bangumiID).toSet(), {1, 2});
    expect(
        client.files['/kazumiSync/collection-devices-v1/device-a.json'], first);
    expect(
        client.files.keys.where((p) =>
            p.startsWith('/kazumiSync/collection-devices-v1/') &&
            p.endsWith('.json')),
        hasLength(2));
    await copyBoxes();
    await webDav.syncCollectibles();
    expect(GStorage.collectChanges.length, 2);
  });

  test('disabling WebDAV clears both dependent flags', () async {
    await GStorage.putSetting(SettingsKeys.webDavEnable, true);
    await GStorage.putSetting(SettingsKeys.webDavEnableHistory, true);
    await GStorage.putSetting(SettingsKeys.webDavEnableCollect, true);

    await webDav.setEnabled(false);

    expect(GStorage.getSetting(SettingsKeys.webDavEnable), isFalse);
    expect(GStorage.getSetting(SettingsKeys.webDavEnableHistory), isFalse);
    expect(GStorage.getSetting(SettingsKeys.webDavEnableCollect), isFalse);
  });

  test('failed WebDAV initialization clears the previous connection', () async {
    webDav.initialized = true;

    await expectLater(webDav.init(), throwsException);

    expect(webDav.initialized, isFalse);
    await expectLater(webDav.setEnabled(true), throwsException);
    expect(GStorage.getSetting(SettingsKeys.webDavEnable), isFalse);
  });
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _MemoryDav implements dav.Client {
  final files = <String, String>{};
  @override
  Future<void> mkdir(String p, [CancelToken? token]) async {}
  @override
  Future<List<dav.File>> readDir(String p, [CancelToken? token]) async => [
        for (final name in files.keys)
          if (name.startsWith('$p/') &&
              !name.substring(p.length + 1).contains('/'))
            dav.File(name: name.substring(p.length + 1), isDir: false),
      ];
  @override
  Future<void> read2File(String p, String dest,
      {void Function(int, int)? onProgress, CancelToken? cancelToken}) async {
    // Hive legacy files are encoded for this in-memory transport only.
    final value = files[p]!;
    await File(dest).writeAsBytes(base64Decode(value.startsWith('bytes:')
        ? value.substring(6)
        : base64Encode(utf8.encode(value))));
  }

  @override
  Future<void> writeFromFile(String source, String p,
      {void Function(int, int)? onProgress, CancelToken? cancelToken}) async {
    final bytes = await File(source).readAsBytes();
    files[p] = source.endsWith('.json')
        ? utf8.decode(bytes)
        : 'bytes:${base64Encode(bytes)}';
  }

  @override
  Future<void> rename(String source, String dest, bool overwrite,
      [CancelToken? token]) async {
    files[dest] = files.remove(source)!;
  }

  @override
  Future<void> remove(String p, [CancelToken? token]) async {
    files.remove(p);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
