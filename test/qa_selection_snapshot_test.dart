import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import '../tools/qa/source_batch/selection_snapshot.dart';

void main() {
  test(
      'tail mode is opt-in and rejects non-selection, non-App and non-boolean input',
      () {
    expect(qaSelectionTailEnabled({}), false);
    expect(qaSelectionTailEnabled({'selection_tail1': false}), false);
    expect(
        qaSelectionTailEnabled(
            {'selection_tail1': true, 'selection_only': true, 'engine': 'app'}),
        true);
    for (final c in [
      {'selection_tail1': true, 'selection_only': false, 'engine': 'app'},
      {'selection_tail1': true, 'selection_only': true, 'engine': 'gecko'},
      {'selection_tail1': 'true', 'selection_only': true, 'engine': 'app'},
      {'selection_tail1': null}
    ]) {
      expect(() => qaSelectionTailEnabled(c), throwsFormatException);
    }
  });
  test(
      'head2 plus tail1 deduplicates by original index for empty and short lists',
      () {
    for (var count = 0; count < 5; count++) {
      final row = qaSelectionSnapshot([
        Road(
            name: '线路',
            data: List.generate(count, (i) => '/ep-$i'),
            identifier: List.generate(count, (i) => '第${i + 1}集'))
      ], (s) => 'https://example.invalid$s', tail1: true);
      final eps = ((row['roads'] as List).single['episodes'] as List);
      expect(
          eps.map((e) => e['episode_index']).toList(),
          switch (count) {
            0 => [],
            1 => [0],
            2 => [0, 1],
            _ => [0, 1, count - 1]
          });
      expect(row['ordering'], 'unknown');
      expect(eps.length, lessThanOrEqualTo(3));
    }
  });
  test(
      'reversed titles remain in source order and last index is not called latest',
      () {
    final row = qaSelectionSnapshot([
      Road(
          name: '线路',
          data: List.generate(28, (i) => '/ep-$i'),
          identifier: List.generate(28, (i) => '第${28 - i}集'))
    ], (s) => 'https://example.invalid$s', tail1: true);
    final eps = ((row['roads'] as List).single['episodes'] as List);
    expect(eps.map((e) => e['episode_index']), [0, 1, 27]);
    expect(eps.map((e) => e['label']), ['第28集', '第27集', '第1集']);
    expect(row['ordering'], 'unknown');
    expect(jsonEncode(row), isNot(contains('latest')));
  });
  test(
      'tail projection caps at 8 roads and never emits untrusted tail labels or addresses',
      () {
    var calls = 0;
    final rows = List.generate(
        10,
        (r) => Road(
            name: '线路',
            data: ['/one', '/two', '/PRIVATE_SENTINEL'],
            identifier: ['第1集', '第2集', 'https://PRIVATE_SENTINEL']));
    final row = qaSelectionSnapshot(rows, (s) {
      calls++;
      if (s.contains('PRIVATE_SENTINEL')) throw StateError(s);
      return 'https://example.invalid$s';
    }, tail1: true);
    expect((row['roads'] as List).length, 8);
    expect(calls, 24);
    for (final road in row['roads'] as List) {
      final tail = (road['episodes'] as List).last;
      expect(tail['episode_index'], 2);
      expect(tail['label'], isNull);
      expect(tail['episode_page_sha256'], isNull);
      expect(tail['binding_available'], false);
    }
    expect(jsonEncode(row), isNot(contains('PRIVATE_SENTINEL')));
  });
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
