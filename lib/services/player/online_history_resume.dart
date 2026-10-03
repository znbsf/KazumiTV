import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/utils/episode_url.dart';

typedef OnlineHistoryResume = ({int episode, int road, int offset});

OnlineHistoryResume? resolveOnlineHistoryResume({
  required History? history,
  required List<Road> roads,
  required String baseUrl,
  required String currentSrc,
  required bool playResume,
}) {
  if (history == null ||
      HistoryEntryKind.normalize(history.entryKind) !=
          HistoryEntryKind.online) {
    return null;
  }
  // A newly selected source must not inherit another series' saved position.
  // Empty source metadata is the legacy compatibility path.
  if (history.lastSrc.isNotEmpty &&
      normalizeEpisodeUrl(baseUrl, history.lastSrc) !=
          normalizeEpisodeUrl(baseUrl, currentSrc)) {
    return null;
  }
  final progress = history.progresses[history.lastWatchEpisode];
  if (progress == null ||
      progress.episode <= 0 ||
      progress.episode != history.lastWatchEpisode) {
    return null;
  }
  final seconds = progress.progress.inSeconds;
  final offset = playResume && seconds > 0 ? seconds : 0;
  final savedUrl = normalizeEpisodeUrl(baseUrl, history.episodePageUrl);
  if (savedUrl.isNotEmpty) {
    final preferredRoad = progress.road;
    final indices = [
      if (preferredRoad >= 0 && preferredRoad < roads.length) preferredRoad,
      for (var i = 0; i < roads.length; i++)
        if (i != preferredRoad) i,
    ];
    for (final roadIndex in indices) {
      final road = roads[roadIndex];
      for (var i = 0; i < road.data.length && i < road.identifier.length; i++) {
        if (normalizeEpisodeUrl(baseUrl, road.data[i]) == savedUrl) {
          return (episode: i + 1, road: roadIndex, offset: offset);
        }
      }
    }
    // A known missing page is not an index match to a different episode.
    return null;
  }
  final roadIndex = progress.road;
  if (roadIndex < 0 || roadIndex >= roads.length) {
    return null;
  }
  final road = roads[roadIndex];
  if (progress.episode > road.data.length ||
      progress.episode > road.identifier.length) {
    return null;
  }
  return (episode: progress.episode, road: roadIndex, offset: offset);
}
