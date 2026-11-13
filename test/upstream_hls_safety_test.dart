import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/utils/m3u8_parser.dart';
import 'package:kazumi/utils/m3u8_ad_filter.dart';

void main() {
  for (final groups in <List<int>>[
    [],
    [1],
    [0, 0],
    [1, 1],
    [1, 1, 2],
    [1, 0, 0]
  ]) {
    test('local discontinuities follow actual boundaries $groups', () {
      final segments = [
        for (var i = 0; i < groups.length; i++)
          M3u8Segment(
              duration: 10,
              uri: 'https://fixture.invalid/$i.ts',
              discontinuityGroup: groups[i])
      ];
      final output = M3u8Parser.buildLocalM3u8(segments, targetDuration: 10);
      final boundaries = [
        for (var i = 1; i < groups.length; i++)
          if (groups[i] != groups[i - 1]) i
      ];
      expect(
          '#EXT-X-DISCONTINUITY'.allMatches(output).length, boundaries.length);
      expect('#EXTINF:'.allMatches(output).length, groups.length);
    });
  }
  test('short opening and ending are retained without independent ad evidence',
      () {
    final segments = [
      for (final (i, d) in [12.0, 600.0, 25.0].indexed)
        M3u8Segment(
            duration: d,
            uri: 'https://fixture.invalid/$i.ts',
            discontinuityGroup: i)
    ];
    expect(M3u8AdFilter.filterAds(segments), segments);
    expect(
        M3u8AdFilter.filterAds(segments, confirmedAdGroups: {1})
            .map((s) => s.discontinuityGroup),
        [0, 2]);
  });
}
