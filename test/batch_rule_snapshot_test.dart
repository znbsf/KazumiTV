import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/plugins.dart';
import '../tools/qa/source_batch/rule_snapshot.dart';
import '../tools/qa/source_batch/qa_rule_fingerprint.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final base = Plugin.fromTemplate()
    ..name = 'Synthetic comparison'
    ..searchList = '//li'
    ..searchName = '//h3'
    ..searchResult = '//a';

  test('independent plain snapshots use production selectors without overlay',
      () {
    final before = BatchRuleSnapshot.fromJson(base.toJson());
    final after = BatchRuleSnapshot.fromJson(
        {...base.toJson(), 'searchList': '//article'});
    const html = '<li><h3>Base</h3><a href="/base"></a></li>'
        '<article><h3>Candidate</h3><a href="/candidate"></a></article>';
    expect(before.plugin.parseHarvestedSearch(html)!.data.single.name, 'Base');
    expect(
        after.plugin.parseHarvestedSearch(html)!.data.single.name, 'Candidate');
    expect(base.searchList, '//li');
    expect(before.identity['effective_sha256'],
        QaRuleFingerprint.fingerprint(base.toJson()));
    expect(after.identity['effective_sha256'],
        isNot(before.identity['effective_sha256']));
    expect(after.identity['overlay'], false);
    expect(after.identity['upstream_commit'], isNull);
    expect(after.identity['base_sha256'], isNull);
  });

  test('production import still rejects invalid API and empty names', () {
    for (final patch in <Map<String, dynamic>>[
      {'api': '999'},
      {'api': 'invalid'},
      {'name': '  '}
    ]) {
      expect(() => BatchRuleSnapshot.fromJson({...base.toJson(), ...patch}),
          throwsFormatException);
    }
  });

  test('postponed overlay documents and variants fail before execution', () {
    for (final metadata in <Map<String, dynamic>>[
      {'kind': 'kazumi-tv-rule-overlay'},
      {'kazumiTvOverlay': {}}
    ]) {
      expect(() => BatchRuleSnapshot.fromJson({...base.toJson(), ...metadata}),
          throwsFormatException);
    }
    for (final variant in ['base', 'other']) {
      expect(() => BatchRuleSnapshot.fromJson(base.toJson(), variant: variant),
          throwsFormatException);
    }
  });

  test('canonical digest retains historical sorted UTF-8 JSON algorithm', () {
    expect(QaRuleFingerprint.fingerprint({'b': 2, 'a': 1}),
        '43258cff783fe7036d8a43033f830adfc60ec037382473548ac742b888292777');
    expect(QaRuleFingerprint.fingerprint({'a': 1, 'b': 2}),
        QaRuleFingerprint.fingerprint({'b': 2, 'a': 1}));
  });
}
