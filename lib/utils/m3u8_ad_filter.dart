import 'package:kazumi/utils/m3u8_parser.dart';

class M3u8AdFilter {
  /// A discontinuity or short duration is not evidence of advertising.
  /// Downloaded files must retain every uncertain group. Only a caller with
  /// independent, explicit evidence may supply confirmed ad groups.
  static List<M3u8Segment> filterAds(List<M3u8Segment> segments,
      {Set<int> confirmedAdGroups = const {}}) {
    if (confirmedAdGroups.isEmpty) return segments;
    return segments
        .where((s) => !confirmedAdGroups.contains(s.discontinuityGroup))
        .toList();
  }

  /// Calculate the new target duration after filtering
  static double calculateTargetDuration(List<M3u8Segment> segments) {
    if (segments.isEmpty) return 0;
    double maxSegDuration = 0;
    for (final seg in segments) {
      if (seg.duration > maxSegDuration) {
        maxSegDuration = seg.duration;
      }
    }
    return maxSegDuration;
  }
}
