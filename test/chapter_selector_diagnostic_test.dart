import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/plugins.dart';
import '../tools/qa/source_batch/qa_rule_fingerprint.dart';

import '../tools/qa/source_batch/chapter_selector_diagnostic.dart';

const _origin = 'https://example.invalid';
const _correctUrl = '$_origin/play/expected';
const _dom = '<html><body>'
    '<ul id="unrelated"><li><a href="/other">Other</a></li></ul>'
    '<div class="hl-play-source"><ul class="hl-plays-list" id="episodes">'
    '<li><a href="/play/expected">第 01 话</a></li>'
    '<li><a href="/play/next">第02话</a></li>'
    '</ul></div></body></html>';

String _hash(String text) => sha256.convert(utf8.encode(text)).toString();

Map<String, dynamic> _base({String roads = '//ul[@id="unrelated"]'}) =>
    (Plugin.fromTemplate()
          ..name = 'aafun'
          ..api = '4'
          ..version = '1.2'
          ..baseUrl = _origin
          ..chapterRoads = roads
          ..chapterResult = './/li/a')
        .toJson();

Map<String, dynamic> _semantic() => (Plugin.fromTemplate()
      ..name = 'moonci'
      ..api = '9'
      ..version = '1.1'
      ..baseUrl = _origin
      ..searchURL = 'https://example.invalid/different-search'
      ..useLegacyParser = true
      ..chapterRoads =
          '//div[contains(@class,"hl-play-source")]//ul[contains(@class,"hl-plays-list")]'
      ..chapterResult = './/a[contains(@href,"/play/")]')
    .toJson();

Map<String, Object?> _compare({
  String raw = _dom,
  Map<String, dynamic>? base,
  Map<String, dynamic>? semantic,
  String? expectedHash,
  String label = '第01话',
}) =>
    ChapterSelectorDiagnostic.compare(
      rawHtml: raw,
      baseRuleJson: base ?? _base(),
      semanticRuleJson: semantic ?? _semantic(),
      expectedEpisodeSha256: expectedHash ?? _hash(_correctUrl),
      expectedEpisodeLabel: label,
    );

Map<String, Object?> _side(Map<String, Object?> result, String name) =>
    result[name]! as Map<String, Object?>;

void main() {
  test('synthetic same DOM distinguishes wrong list; only two fields change',
      () {
    final base = _base(), semantic = _semantic();
    final before = jsonEncode([base, semantic]);
    final result = _compare(base: base, semantic: semantic);
    expect(result['status'], 'observed');
    expect(result['body_sha256'], _hash(_dom));
    expect(_side(result, 'base')['contains_expected_exact'], isFalse);
    expect(_side(result, 'candidate')['contains_expected_exact'], isTrue);
    expect(_side(result, 'candidate')['episode_count'], 2);
    expect(_side(result, 'comparison')['ordered_selection_equal'], isFalse);
    final expected = Plugin.fromJson(base).toJson()
      ..['chapterRoads'] = semantic['chapterRoads']
      ..['chapterResult'] = semantic['chapterResult'];
    expect(_side(result, 'candidate_rule')['normalized_sha256'],
        QaRuleFingerprint.fingerprint(Plugin.fromJson(expected).toJson()));
    expect(_side(result, 'candidate_rule')['api'], '4');
    expect(_side(result, 'candidate_rule')['name'], 'aafun');
    expect(jsonEncode([base, semantic]), before);
    expect(result['verdict'], 'diagnostic_only_no_rule_or_playback_acceptance');
  });

  test('same exact selection supplies observation for withdrawing hypothesis',
      () {
    final result = _compare(base: _base(roads: '//ul[@id="episodes"]'));
    expect(_side(result, 'comparison')['ordered_selection_equal'], isTrue);
    expect(_side(result, 'base')['contains_expected_exact'], isTrue);
    expect(_side(result, 'candidate')['contains_expected_exact'], isTrue);
  });

  for (final field in ['chapterRoads', 'chapterResult']) {
    test('invalid $field yields typed error, never selector/response text', () {
      final base = _base()..[field] = '//[https://secret.invalid/PRIVATE_TOKEN';
      final result = _compare(base: base);
      expect(_side(result, 'base')['status'], 'error');
      expect(_side(result, 'base')['error_type'], 'XPathRuleFormatException');
      expect(_side(result, 'base')['field'], field);
      expect(_side(result, 'candidate')['status'], 'parsed');
      expect(_side(result, 'comparison')['ordered_selection_equal'], isNull);
      expect(jsonEncode(result), isNot(contains('PRIVATE_TOKEN')));
      expect(jsonEncode(result), isNot(contains('secret.invalid')));
    });
  }

  test('empty and whitespace responses are explicitly rejected', () {
    for (final raw in ['', ' \n\t ']) {
      final result = _compare(raw: raw);
      expect(result['status'], 'rejected');
      expect(result['error_type'], 'empty_html');
      expect(result['body_sha256'], _hash(raw));
      expect(result.containsKey('base'), isFalse);
    }
  });

  test('byte limit includes multibyte UTF8 and accepts exact bound', () {
    final atLimit = _compare(raw: 'x' * ChapterSelectorDiagnostic.maxHtmlBytes);
    expect(atLimit['status'], 'observed');
    expect(_side(atLimit, 'base')['episode_count'], 0);
    for (final raw in [
      'x' * (ChapterSelectorDiagnostic.maxHtmlBytes + 1),
      '汉' * (ChapterSelectorDiagnostic.maxHtmlBytes ~/ 3 + 1),
    ]) {
      final result = _compare(raw: raw);
      expect(result['error_type'], 'html_size_limit');
      expect(result.containsKey('base'), isFalse);
    }
  });

  test('URLs, credentials, header-like labels and oversized text stay private',
      () {
    const secretUrl =
        'https://user:PRIVATE_PASSWORD@private.invalid/a?token=PRIVATE_TOKEN';
    final base = _base(roads: '//ul')
      ..['name'] = 'https://PRIVATE_RULE.invalid/'
      ..['version'] = 'Cookie: PRIVATE_COOKIE'
      ..['userAgent'] = 'PRIVATE_HEADER'
      ..['referer'] = secretUrl;
    final semantic = _semantic()..['chapterRoads'] = '//ul';
    final raw = '<ul><li><a href="$secretUrl">'
        'Authorization: Bearer PRIVATE_AUTH Cookie: PRIVATE_COOKIE</a></li>'
        '<li><a href="/play/other">${'长' * 200}</a></li></ul>';
    final result = _compare(
        raw: raw,
        base: base,
        semantic: semantic,
        // Production normalization removes userinfo; hash the normalized URL.
        expectedHash: _hash('https://private.invalid/a?token=PRIVATE_TOKEN'),
        label: 'Cookie: PRIVATE_EXPECTED');
    final encoded = jsonEncode(result);
    for (final secret in [
      'private.invalid',
      'PRIVATE_',
      secretUrl,
      '<ul>',
      '长长长长',
    ]) {
      expect(encoded, isNot(contains(secret)));
    }
    expect(result['expected_label'], '[redacted]');
    expect(_side(result, 'base_rule')['name'], '[redacted]');
    final samples = _side(result, 'base')['samples']! as List;
    expect(samples.every((sample) => sample['label'] == '[redacted]'), isTrue);
    expect(_side(result, 'base')['contains_expected_hash'], isTrue);
    expect(_side(result, 'base')['contains_expected_exact'], isFalse);
  });

  test('samples are bounded while counts and late targets remain accurate', () {
    final raw = StringBuffer('<html><body>');
    for (var road = 0; road < 10; road++) {
      raw.write('<ul>');
      for (var ep = 0; ep < 10; ep++) {
        raw.write('<li><a href="/play/$road-$ep">EP$ep</a></li>');
      }
      raw.write('<li><a href="/play/expected">第01话</a></li></ul>');
    }
    raw.write('</body></html>');
    final result = _compare(
        raw: raw.toString(),
        base: _base(roads: '//ul'),
        semantic: _semantic()
          ..['chapterRoads'] = '//ul'
          ..['chapterResult'] = './/li/a');
    for (final name in ['base', 'candidate']) {
      final side = _side(result, name);
      expect(side['road_count'], 10);
      expect(side['episode_count'], 110);
      expect(side['expected_exact_matches'], 10);
      final samples = side['samples']! as List;
      expect(samples.length,
          lessThanOrEqualTo(ChapterSelectorDiagnostic.maxSamplesPerVariant));
      expect(samples.any((sample) => sample['episode_index'] == 10), isTrue);
    }
    expect(jsonEncode(result).length, lessThan(10000));
  });

  test(
      'schema/input errors and cross-origin or API rules fail without raw data',
      () {
    final malformed = _base()..['name'] = ['PRIVATE_SCHEMA'];
    expect(_compare(base: malformed)['status'], 'rejected');
    expect(jsonEncode(_compare(base: malformed)), isNot(contains('PRIVATE_')));
    expect(_compare(expectedHash: 'PRIVATE_BAD_HASH')['error_type'],
        'invalid_expected_identity');
    for (final semantic in [
      _semantic()..['baseURL'] = 'https://different.invalid',
      _semantic()..['chapterMode'] = 'api',
    ]) {
      expect(_compare(semantic: semantic)['error_type'],
          'requires_same_origin_xpath_rules');
    }
  });
}
