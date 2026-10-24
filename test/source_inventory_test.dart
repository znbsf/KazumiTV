import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/plugins.dart';
import '../tools/qa/source_batch/qa_rule_fingerprint.dart';
import '../tools/qa/source_batch/source_inventory.dart';

Map<String, dynamic> rule(String name) => (Plugin.fromTemplate()
      ..name = name
      ..version = '1.0'
      ..baseUrl = 'https://example.invalid/')
    .toJson();

Future<Directory> snapshot(List<Map<String, dynamic>> rules,
    {List<Map<String, dynamic>>? catalog}) async {
  final root = await Directory.systemTemp.createTemp('source_inventory_');
  await Directory('${root.path}/rules').create();
  final index = catalog ??
      [
        for (final r in rules) {'name': r['name'], 'version': r['version']}
      ];
  final indexBytes = utf8.encode(jsonEncode(index));
  await File('${root.path}/index.json').writeAsBytes(indexBytes);
  final entries = <Map<String, dynamic>>[];
  final writtenNames = <String>{};
  for (var i = 0; i < rules.length; i++) {
    final name = index[i]['name'];
    final bytes = utf8.encode(jsonEncode(rules[i]));
    // Match acquisition: duplicate names are rejected before a second write.
    if (writtenNames.add(name.toString().toLowerCase())) {
      await File('${root.path}/rules/$name.json').writeAsBytes(bytes);
    }
    entries.add({
      'catalog_position': i,
      'name': name,
      'index_version': index[i]['version'],
      'fetch_status': 'downloaded',
      'raw_path': 'rules/$name.json',
      'raw_sha256': sha256.convert(bytes).toString(),
      'git_blob_sha1': sha1.convert(
          [...utf8.encode('blob ${bytes.length}\u0000'), ...bytes]).toString(),
    });
  }
  await File('${root.path}/source_inventory_download.json')
      .writeAsString(jsonEncode({
    'schema_version': 1,
    'repository': 'Predidit/KazumiRules',
    'default_branch': 'main',
    'commit': 'ba8e10b35b0c3a56bbb6032a12356b0473844c64',
    'index_sha256': sha256.convert(indexBytes).toString(),
    'catalog_rows': entries.length,
    'entries': entries,
    'source_verification': 'synthetic_fixture_not_upstream_evidence',
  }));
  return root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('declaration is not an observed challenge and never excludes the source',
      () async {
    final captcha = rule('Captcha');
    (captcha['antiCrawlerConfig'] as Map)['enabled'] = true;
    final root = await snapshot([
      rule('Plain'),
      captcha,
      {...rule('Old'), 'deprecated': true},
    ]);
    try {
      final inventory = await SourceInventory.generate(root);
      final counts = inventory['counts'] as Map;
      expect(counts['catalog_rows'], 3);
      expect(counts['qualified'], 2);
      expect(counts['declared_captcha_attemptable'], 1);
      expect(counts['no_declared_captcha_attemptable'], 1);
      expect(counts['excluded_deprecated'], 1);
      expect(counts['skipped_after_actual_challenge'], 0);
      expect(counts['actual_challenge_status_unknown'], 2);
      expect((inventory['plans'] as List).first['cases'], hasLength(2));
      final entry = (inventory['entries'] as List).first;
      expect(
          entry['normalized_sha256'],
          QaRuleFingerprint.fingerprint(
              Plugin.fromJson(rule('Plain')).toJson()));
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('future APIs are rejected by the production importer', () async {
    final root = await snapshot([
      {...rule('Future'), 'api': '999'}
    ]);
    try {
      final inventory = await SourceInventory.generate(root);
      expect((inventory['counts'] as Map)['qualified'], 0);
      expect((inventory['entries'] as List).single['validation'],
          'production_import_rejected');
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('duplicates and payload/version mismatch stay in the denominator',
      () async {
    final root = await snapshot([
      rule('Alpha'),
      rule('ALPHA'),
      rule('WrongPayload'),
      rule('Version')
    ], catalog: [
      {'name': 'Alpha', 'version': '1.0'},
      {'name': 'ALPHA', 'version': '1.0'},
      {'name': 'Expected', 'version': '1.0'},
      {'name': 'Version', 'version': '2.0'},
    ]);
    try {
      final inventory = await SourceInventory.generate(root);
      expect((inventory['counts'] as Map)['catalog_rows'], 4);
      expect((inventory['counts'] as Map)['qualified'], 1);
      expect((inventory['counts'] as Map)['invalid_or_gap'], 3);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('tampered bytes are not normalized into a plausible valid rule',
      () async {
    final root = await snapshot([rule('Plain')]);
    try {
      await File('${root.path}/rules/Plain.json')
          .writeAsString(jsonEncode(rule('Changed')));
      final inventory = await SourceInventory.generate(root);
      expect((inventory['counts'] as Map)['qualified'], 0);
      expect(
          (inventory['entries'] as List).single['validation'], 'invalid_rule');
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('all waves contain at most 24 cases with distinct work alternatives',
      () async {
    final root =
        await snapshot([for (var i = 0; i < 25; i++) rule('Source$i')]);
    try {
      final inventory = await SourceInventory.generate(root);
      final plans = inventory['plans'] as List;
      expect(plans, hasLength(6));
      expect(plans.every((p) => (p['cases'] as List).length <= 24), isTrue);
      final entry = (inventory['entries'] as List).first;
      final cases = entry['candidate_cases'] as List;
      expect(cases.map((c) => c['work_key']).toSet(), hasLength(3));
      expect(cases.every((c) => c['canonical_subject_id'] == null), isTrue);
      await SourceInventory.write(root, inventory);
      expect(await File('${root.path}/plans/wave-1-batch-1.json').exists(),
          isTrue);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
