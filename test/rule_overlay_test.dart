import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/plugin/plugin_http_module.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/plugins/rule_overlay.dart';
import 'package:kazumi/services/plugin/plugin_import_parser.dart';
import 'package:kazumi/utils/encoding.dart';

const _commit = 'ba8e10b35b0c3a56bbb6032a12356b0473844c64';

Plugin _base([String name = 'Overlay fixture']) => Plugin.fromTemplate()
  ..name = name
  ..version = '1.0'
  ..baseUrl = 'https://example.invalid/'
  ..searchURL = 'https://example.invalid/search?q=@keyword'
  ..searchList = '//li'
  ..searchName = '//h3'
  ..searchResult = '//a'
  ..chapterRoads = '//ul'
  ..chapterResult = '//a';

RuleOverlay _overlay(Plugin base, [Map<String, dynamic>? overrides]) =>
    RuleOverlay.create(
      repository: 'Predidit/KazumiRules',
      commit: _commit,
      baseRule: base.toJson(),
      overrides: overrides ?? {'searchList': '//article'},
    );

Map<String, dynamic> _copy(Map<String, dynamic> json) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(json)) as Map);

PluginHTTPItem _catalogItem(String name) => PluginHTTPItem(
    name: name,
    version: '2.0',
    useNativePlayer: true,
    author: '',
    lastUpdate: 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('imported overlay drives the production XPath search and survives save',
      () async {
    final base = _base();
    final bundle = _overlay(base);
    final imported = PluginImportParser.parse(jsonEncode(bundle.toJson()));
    expect(imported.failures, isEmpty);
    final effective = imported.plugins.single;
    const html = '<li><h3>Old</h3><a href="/old"></a></li>'
        '<article><h3>Correct</h3><a href="/correct"></a></article>';
    expect(base.parseHarvestedSearch(html)!.data.single.name, 'Old');
    expect(effective.parseHarvestedSearch(html)!.data.single.name, 'Correct');
    expect(base.searchList, '//li');

    late String stored;
    final controller =
        PluginsController(pluginJsonWriter: (json) async => stored = json);
    await controller.updatePlugins(imported.plugins);
    final restored = Plugin.fromJson(
        Map<String, dynamic>.from((jsonDecode(stored) as List).single as Map));
    expect(restored.parseHarvestedSearch(html)!.data.single.src, '/correct');
    expect(restored.tvOverlay!.commit, _commit);
    expect(restored.tvOverlay!.baseSha256, bundle.baseSha256);
    expect(restored.toJson(), effective.toJson());
  });

  test('share links and arrays preserve overlay metadata', () {
    final plugin = Plugin.fromOverlay(_overlay(_base()));
    final shared = jsonToKazumiBase64(jsonEncode(plugin.toJson()));
    final result = PluginImportParser.parse(jsonEncode([shared]));
    expect(result.failures, isEmpty);
    expect(result.plugins.single.tvOverlay, isNotNull);
    expect(result.plugins.single.searchList, '//article');
  });

  test('offline generator produces an importable file and refuses overwrite',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('rule_overlay_cli_');
    try {
      final baseFile =
          File([directory.path, 'base.json'].join(Platform.pathSeparator));
      final patchFile =
          File([directory.path, 'patch.json'].join(Platform.pathSeparator));
      final output =
          File([directory.path, 'overlay.json'].join(Platform.pathSeparator));
      await baseFile.writeAsString(jsonEncode([_base().toJson()]));
      await patchFile.writeAsString(jsonEncode({'searchList': '//article'}));
      final args = [
        '--packages=.dart_tool/package_config.json',
        'tools/rules/create_overlay.dart',
        baseFile.path,
        patchFile.path,
        _commit,
        output.path,
      ];
      final generated =
          await Process.run('dart', args, runInShell: Platform.isWindows);
      expect(generated.exitCode, 0, reason: generated.stderr.toString());
      final contents = await output.readAsString();
      final parsed = PluginImportParser.parse(contents);
      expect(parsed.failures, isEmpty);
      expect(parsed.plugins.single.searchList, '//article');
      final duplicate =
          await Process.run('dart', args, runInShell: Platform.isWindows);
      expect(duplicate.exitCode, 1);
      expect(await output.readAsString(), contents);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('hash ignores object key order while checking the complete base', () {
    final rule = _base().toJson();
    final reordered = {
      for (final key in rule.keys.toList().reversed) key: rule[key]
    };
    expect(RuleOverlay.fingerprint(rule), RuleOverlay.fingerprint(reordered));
    final bundle = _copy(_overlay(_base()).toJson());
    (bundle['baseRule'] as Map)['chapterResult'] = '//wrong';
    expect(() => Plugin.fromJson(bundle), throwsFormatException);
  });

  test('rejects changed persisted effective rule rather than losing the edit',
      () {
    final stored = Plugin.fromOverlay(_overlay(_base())).toJson();
    stored['referer'] = 'https://changed.invalid/';
    expect(() => Plugin.fromJson(stored), throwsFormatException);
  });

  for (final field in [
    'name',
    'version',
    'api',
    'searchJS',
    'playJS',
    'captchaScript',
    'antiCrawlerConfig',
    'requestHeaders',
    'webviewMajor',
  ]) {
    test('rejects unsupported or executable override $field', () {
      final bundle = _copy(_overlay(_base()).toJson());
      bundle['overrides'] = {field: 'untrusted'};
      final parsed = PluginImportParser.parse(jsonEncode(bundle));
      expect(parsed.plugins, isEmpty);
      expect(parsed.failureCount, 1);
    });
  }

  test('rejects unknown requirements, future schemas and header injection', () {
    final bundle = _overlay(_base()).toJson();
    expect(
        () => Plugin.fromJson({
              ...bundle,
              'requires': ['unimplemented']
            }),
        throwsFormatException);
    expect(() => Plugin.fromJson({...bundle, 'schemaVersion': 2}),
        throwsFormatException);
    expect(() => Plugin.fromJson({...bundle, 'kind': 'kazumi-tv-future-rule'}),
        throwsFormatException);
    expect(() => _overlay(_base(), {'referer': 'https://x.invalid/\r\nX: y'}),
        throwsFormatException);
    expect(() => _overlay(_base(), {'baseURL': 'file:///tmp/media'}),
        throwsFormatException);
    expect(() => _overlay(_base(), {'usePost': 'true'}), throwsFormatException);
    expect(() => _overlay(_base(), {'searchList': 'x' * 8193}),
        throwsFormatException);
  });

  test('cannot silently normalize a non-normalized base or nest overlays', () {
    final bundle = _overlay(_base()).toJson();
    final sparseBase = <String, dynamic>{
      'api': '9',
      'name': 'Sparse',
      'version': '1.0'
    };
    expect(
        () => Plugin.fromJson({
              ...bundle,
              'baseRule': sparseBase,
              'baseSha256': RuleOverlay.fingerprint(sparseBase),
            }),
        throwsFormatException);
    expect(() => _overlay(Plugin.fromOverlay(_overlay(_base()))),
        throwsFormatException);
  });

  test('API source template overlay keeps the API request and base intact', () {
    final base = _base()..searchMode = 'api';
    base.searchApiConfig.request.url = 'https://example.invalid/suggest';
    final plugin = Plugin.fromOverlay(_overlay(base, {
      'searchApiConfig.sourceTemplate': 'https://example.invalid/GV@source'
    }));
    expect(plugin.searchApiConfig.sourceTemplate,
        'https://example.invalid/GV@source');
    expect(
        plugin.searchApiConfig.request.url, base.searchApiConfig.request.url);
    expect(base.searchApiConfig.sourceTemplate, isEmpty);
    expect(
        () => Plugin.fromOverlay(_overlay(_base(), {
              'searchApiConfig.sourceTemplate':
                  'https://example.invalid/@source'
            })),
        throwsFormatException);
  });

  test(
      'individual upstream update preserves overlay; explicit rollback unlocks it',
      () async {
    var writes = 0;
    final local = Plugin.fromOverlay(_overlay(_base()));
    final remote = _base()..version = '2.0';
    final controller = PluginsController(
      pluginLoader: (_) async => remote,
      pluginJsonWriter: (_) async => writes++,
    )..pluginList.add(local);
    expect(await controller.tryUpdatePluginByName(local.name),
        PluginUpdateResult.overlayConflict);
    expect(controller.pluginList.single, same(local));
    expect(writes, 0);
    await controller.restorePluginBase(local);
    expect(controller.pluginList.single.tvOverlay, isNull);
    expect(controller.pluginList.single.searchList, '//li');
    expect(writes, 1);
    expect(await controller.tryUpdatePluginByName(local.name),
        PluginUpdateResult.updated);
    expect(controller.pluginList.single.version, '2.0');
  });

  test('batch update reports protected overlays while updating ordinary rules',
      () async {
    final local = Plugin.fromOverlay(_overlay(_base()));
    var writes = 0;
    final controller = PluginsController(
      catalogLoader: () async =>
          [_catalogItem(local.name), _catalogItem('Plain')],
      pluginLoader: (name) async => _base(name)..version = '2.0',
      pluginJsonWriter: (_) async => writes++,
    )..pluginList.addAll([local, _base('Plain')]);
    final result = await controller.tryUpdateAllPlugin();
    expect(result.candidates, 2);
    expect(result.updated, 1);
    expect(result.overlayConflicts, 1);
    expect(result.failed, 0);
    expect(writes, 1);
    expect(controller.pluginList.first, same(local));
    expect(controller.pluginList.last.version, '2.0');
  });

  test('failed rollback persistence preserves the active overlay', () async {
    final local = Plugin.fromOverlay(_overlay(_base()));
    final controller = PluginsController(
      pluginJsonWriter: (_) async => throw StateError('disk unavailable'),
      errorReporter: (_, __, ___) {},
    )..pluginList.add(local);
    await expectLater(controller.restorePluginBase(local), throwsStateError);
    expect(controller.pluginList.single, same(local));
  });

  test('stale rollback cannot replace a newer explicitly imported rule',
      () async {
    var writes = 0;
    final old = Plugin.fromOverlay(_overlay(_base()));
    final replacement = _base()..version = '3.0';
    final controller = PluginsController(
      pluginJsonWriter: (_) async => writes++,
      errorReporter: (_, __, ___) {},
    )..pluginList.add(replacement);
    await expectLater(controller.restorePluginBase(old), throwsStateError);
    expect(controller.pluginList.single, same(replacement));
    expect(writes, 0);
  });

  test('network rule loader cannot activate a local overlay document',
      () async {
    final remote = Plugin.fromOverlay(_overlay(_base()..version = '2.0'));
    final controller = PluginsController(
      pluginLoader: (_) async => remote,
      pluginJsonWriter: (_) async => fail('must not persist remote overlay'),
      errorReporter: (_, __, ___) {},
    );
    expect(await controller.tryUpdatePluginByName(remote.name),
        PluginUpdateResult.failed);
    expect(controller.pluginList, isEmpty);
  });
}
