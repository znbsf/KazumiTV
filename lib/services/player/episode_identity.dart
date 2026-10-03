import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/utils/async_session.dart';
import 'package:kazumi/utils/episode_url.dart';

/// A chapter page and the label supplied by its source.
///
/// Page identity is only valid within the same source. Build road identities
/// with [episodeIdentitiesForRoad] to reuse the source URL normalization.
final class EpisodeIdentity {
  const EpisodeIdentity({required this.title, required this.pageUrl});

  final String title;
  final String pageUrl;
}

/// Reads a one-based episode selection without borrowing another list index.
EpisodeIdentity? episodeIdentityForRoad(
  Road road,
  int episode, {
  required String baseUrl,
}) {
  final index = episode - 1;
  if (index < 0 ||
      index >= road.data.length ||
      index >= road.identifier.length) {
    return null;
  }
  final pageUrl = normalizeEpisodeUrl(baseUrl, road.data[index]);
  if (pageUrl.isEmpty) return null;
  return EpisodeIdentity(title: road.identifier[index], pageUrl: pageUrl);
}

/// Candidate indices remain the road's zero-based indices.
///
/// Entries missing their display label are omitted at the end. Empty URLs stay
/// at their original indices but cannot match a playable episode.
List<EpisodeIdentity> episodeIdentitiesForRoad(
  Road road, {
  required String baseUrl,
}) {
  final count = road.data.length < road.identifier.length
      ? road.data.length
      : road.identifier.length;
  return List.generate(
    count,
    (index) => EpisodeIdentity(
      title: road.identifier[index],
      pageUrl: normalizeEpisodeUrl(baseUrl, road.data[index]),
    ),
    growable: false,
  );
}

final _ordinaryEpisodeLabel = RegExp(
  r'^(?:(?:第|ep(?:isode)?)\s*)?([0-9]{1,4})(?:\s*[集话話回])?$',
  caseSensitive: false,
);

/// Parses only a complete normal episode label, never a number inside a title.
///
/// Full-width digits and common EP/第/集 labels are harmless variations. Labels
/// for trailers, SP/OVA, decimals, seasons, or named chapters need a manual
/// selection even when they contain the same number.
int? ordinaryEpisodeOrdinal(String title) {
  final normalized = String.fromCharCodes(title.trim().runes.map((rune) {
    if (rune >= 0xff01 && rune <= 0xff5e) return rune - 0xfee0;
    return rune;
  }));
  final match = _ordinaryEpisodeLabel.firstMatch(normalized);
  if (match == null) return null;
  final ordinal = int.tryParse(match.group(1)!);
  return ordinal != null && ordinal > 0 ? ordinal : null;
}

/// Returns one unique zero-based match, or asks the caller for manual selection.
///
/// A unique same-source page takes precedence over labels. Across sources, page
/// URLs are never evidence of equivalence; the user must first select the same
/// work and season, then only a unique normal episode ordinal can match. A null
/// result must not fall back to the old array position or playback offset.
int? matchingEpisodeIdentity(
  EpisodeIdentity current,
  List<EpisodeIdentity> candidates, {
  bool acrossSources = false,
}) {
  if (!acrossSources && current.pageUrl.isNotEmpty) {
    int? exact;
    for (var index = 0; index < candidates.length; index++) {
      if (candidates[index].pageUrl != current.pageUrl) continue;
      if (exact != null) return null;
      exact = index;
    }
    if (exact != null) return exact;
  }

  final ordinal = ordinaryEpisodeOrdinal(current.title);
  if (ordinal == null) return null;
  int? matched;
  for (var index = 0; index < candidates.length; index++) {
    final candidate = candidates[index];
    if (candidate.pageUrl.isEmpty ||
        ordinaryEpisodeOrdinal(candidate.title) != ordinal) {
      continue;
    }
    if (matched != null) return null;
    matched = index;
  }
  return matched;
}

/// Seconds captured from actual player position and duration, not start/intro
/// offsets. Unknown duration and invalid positions cannot supply old progress.
int episodeTransferOffset({
  required Duration position,
  required Duration duration,
}) {
  if (position <= Duration.zero || duration <= Duration.zero) return 0;
  return (position > duration ? duration : position).inSeconds;
}

typedef EpisodeTransferSelection = ({int episodeIndex, int offset});

/// Resolves a late chapter response only while its existing session owns it.
///
/// Use the caller's [AsyncSessionOwner] for each new request, manual selection,
/// cancellation, and disposal. Recheck ownership after any subsequent await.
/// Unmatched/manual episodes start at zero; they never inherit this snapshot.
EpisodeTransferSelection? resolveEpisodeTransfer({
  required EpisodeIdentity current,
  required List<EpisodeIdentity> candidates,
  required Duration position,
  required Duration duration,
  required AsyncSession session,
  bool acrossSources = false,
}) {
  if (session.isStale) return null;
  final index = matchingEpisodeIdentity(
    current,
    candidates,
    acrossSources: acrossSources,
  );
  if (index == null) return null;
  return (
    episodeIndex: index,
    offset: episodeTransferOffset(position: position, duration: duration),
  );
}
