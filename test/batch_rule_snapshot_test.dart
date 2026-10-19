import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/rule_overlay.dart';
import '../tools/qa/source_batch/rule_snapshot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final base = Plugin.fromTemplate()
    ..name = 'Synthetic comparison'
    ..searchList = '//li'
    ..searchName = '//h3'
    ..searchResult = '//a';
  final overlay = RuleOverlay.create(
      repository: 'Predidit/KazumiRules',
      commit: 'ba8e10b35b0c3a56bbb6032a12356b0473844c64',
      baseRule: base.toJson(),
      overrides: {'searchList': '//article'});

  test('effective and base comparisons use production selectors independently',
      () {
    final effective = BatchRuleSnapshot.fromJson(overlay.toJson());
    final baseline =
        BatchRuleSnapshot.fromJson(overlay.toJson(), variant: 'base');
    const html = '<li><h3>Base</h3><a href="/base"></a></li>'
        '<article><h3>Covered</h3><a href="/covered"></a></article>';
    expect(effective.plugin.parseHarvestedSearch(html)!.data.single.name,
        'Covered');
    expect(
        baseline.plugin.parseHarvestedSearch(html)!.data.single.name, 'Base');
    expect(base.searchList, '//li');
    expect(baseline.identity['effective_sha256'], overlay.baseSha256);
    expect(effective.identity['effective_sha256'], isNot(overlay.baseSha256));
    expect(baseline.identity['overlay'], false);
    expect(effective.identity['overlay'], true);
    expect(effective.identity['provenance_trust'], 'unverified_source_label');
  });

  test('persisted export and bundle yield the same measured identity', () {
    final saved = Plugin.fromOverlay(overlay).toJson();
    expect(BatchRuleSnapshot.fromJson(saved).identity,
        BatchRuleSnapshot.fromJson(overlay.toJson()).identity);
    expect(BatchRuleSnapshot.fromJson(overlay.toJson()).identity['name'],
        base.name);
    expect(BatchRuleSnapshot.fromJson(overlay.toJson()).identity['version'],
        base.version);
    expect(
        BatchRuleSnapshot.fromJson(overlay.toJson()).identity['api'], base.api);
  });

  test('production import rejects future or invalid API and empty names', () {
    for (final patch in <Map<String, dynamic>>[
      {'api': '999'},
      {'api': 'invalid'},
      {'name': '  '},
    ]) {
      expect(() => BatchRuleSnapshot.fromJson({...base.toJson(), ...patch}),
          throwsFormatException);
    }
  });

  test('plain snapshots preserve effective hash but do not invent provenance',
      () {
    final covered = Plugin.fromOverlay(overlay);
    final plain =
        BatchRuleSnapshot.fromJson(covered.toJson(includeLocalMetadata: false));
    expect(
        plain.identity['effective_sha256'],
        BatchRuleSnapshot.fromJson(overlay.toJson())
            .identity['effective_sha256']);
    expect(plain.identity['upstream_commit'], isNull);
    expect(plain.identity['base_sha256'], isNull);
    expect(plain.identity['overlay_sha256'], isNull);
    expect(() => BatchRuleSnapshot.fromJson(base.toJson(), variant: 'base'),
        throwsFormatException);
  });

  test('invalid bundle and unknown comparison mode fail before execution', () {
    expect(
        () => BatchRuleSnapshot.fromJson(
            {...overlay.toJson(), 'baseSha256': '0' * 64}),
        throwsFormatException);
    expect(() => BatchRuleSnapshot.fromJson(overlay.toJson(), variant: 'other'),
        throwsFormatException);
  });
}
