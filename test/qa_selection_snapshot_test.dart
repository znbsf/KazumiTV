import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import '../tools/qa/source_batch/selection_snapshot.dart';

void main() {
  test(
      'discovery caps roads/episodes while preserving real counts and URI identity',
      () {
    final roads = List.generate(
        10,
        (i) => Road(
            name: '线路$i',
            data: List.generate(3, (j) => '/PRIVATE_SENTINEL-$i-$j'),
            identifier: ['第1集', '第2集', '第3集']));
    var normalizations = 0;
    final result = qaSelectionSnapshot(roads, (path) {
      normalizations++;
      return 'https://example.invalid$path';
    });
    expect(result['road_count'], 10);
    expect(result['roads_truncated'], true);
    final rows = result['roads'] as List;
    expect(rows.length, 8);
    expect(normalizations, 16);
    expect(rows.first['episode_count'], 3);
    expect(
        rows.first['episodes'][0]['episode_page_sha256'],
        sha256
            .convert(
                utf8.encode('https://example.invalid/PRIVATE_SENTINEL-0-0'))
            .toString());
    expect(jsonEncode(result), isNot(contains('PRIVATE_SENTINEL')));
    expect(result['parser'], 'not_run');
    expect(result['media'], 'not_run');
  });
  test('unsafe labels and unusable page addresses cannot become bindings', () {
    final result = qaSelectionSnapshot([
      Road(
          name: 'https://PRIVATE_SENTINEL',
          data: ['bad', 'bad2'],
          identifier: ['https://PRIVATE_SENTINEL', '第2集'])
    ], (_) => 'javascript:PRIVATE_SENTINEL');
    final row = (result['roads'] as List).single;
    expect(row['road_label'], isNull);
    expect(row['episodes'].every((e) => e['binding_available'] == false), true);
    expect(jsonEncode(result), isNot(contains('PRIVATE_SENTINEL')));
  });
  test('mismatched chapter lists are coverage metadata and never normalized',
      () {
    final result = qaSelectionSnapshot([
      Road(name: '线路', data: ['/one'], identifier: [])
    ], (_) => throw StateError('Must not normalize mismatched lists'));
    expect((result['roads'] as List).single['paired_labels'], false);
    expect((result['roads'] as List).single['episodes'], isEmpty);
  });
  test('header-like credentials cannot leak or shift selected episode indices',
      () {
    final result = qaSelectionSnapshot([
      Road(name: 'Authorization: Bearer PRIVATE_SENTINEL', data: [
        '/one',
        '/two',
        '/three'
      ], identifier: [
        'Cookie: PRIVATE_SENTINEL',
        'Bearer PRIVATE_SENTINEL',
        '第3集'
      ])
    ], (path) => 'https://example.invalid$path');
    final row = (result['roads'] as List).single;
    final episodes = row['episodes'] as List;
    expect(row['road_label'], isNull);
    expect(row['episode_count'], 3);
    expect(episodes.map((e) => e['episode_index']), [0, 1]);
    expect(
        episodes.every(
            (e) => e['label'] == null && e['binding_available'] == false),
        true);
    for (final forbidden in [
      'PRIVATE_SENTINEL',
      'Authorization',
      'Cookie',
      'Bearer'
    ]) {
      expect(jsonEncode(result), isNot(contains(forbidden)));
    }
  });
}
