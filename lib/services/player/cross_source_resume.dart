import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/services/player/episode_identity.dart';
import 'package:kazumi/utils/episode_url.dart';

/// An explicitly confirmed transfer, still checked against the destination list.
class CrossSourceResume {
  const CrossSourceResume(
      {required this.bangumiId,
      required this.pluginName,
      required this.src,
      required this.road,
      required this.episode,
      required this.episodePageUrl,
      required this.offset});
  final int bangumiId;
  final String pluginName;
  final String src;
  final int road;
  final int episode;
  final String episodePageUrl;
  final int offset;

  bool matches(
          {required int currentBangumiId,
          required String currentPlugin,
          required String currentSrc,
          required List<Road> roads,
          required String baseUrl}) =>
      bangumiId == currentBangumiId &&
      pluginName == currentPlugin &&
      normalizeEpisodeUrl(baseUrl, src) ==
          normalizeEpisodeUrl(baseUrl, currentSrc) &&
      offset >= 0 &&
      road >= 0 &&
      road < roads.length &&
      episode > 0 &&
      episode <= roads[road].data.length &&
      episode <= roads[road].identifier.length &&
      episodePageUrl.isNotEmpty &&
      normalizeEpisodeUrl(baseUrl, roads[road].data[episode - 1]) ==
          episodePageUrl;
}

/// The most recent online watch may offer an explicit same-work/season choice.
/// No selection is inferred from a destination array index or a special label.
List<CrossSourceResume> crossSourceResumeChoices({
  required Iterable<History> histories,
  required int bangumiId,
  required String pluginName,
  required String src,
  required List<Road> roads,
  required String baseUrl,
}) {
  if (pluginName.isEmpty || src.trim().isEmpty) return const [];
  final previous = histories
      .where((entry) =>
          entry.bangumiItem.id == bangumiId &&
          HistoryEntryKind.normalize(entry.entryKind) ==
              HistoryEntryKind.online)
      .toList()
    ..sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
  if (previous.isEmpty) return const [];
  final history = previous.first;
  if (history.adapterName.isEmpty ||
      history.lastWatchEpisode <= 0 ||
      history.lastSrc.isEmpty ||
      (history.adapterName == pluginName &&
          normalizeEpisodeUrl(baseUrl, history.lastSrc) ==
              normalizeEpisodeUrl(baseUrl, src))) {
    return const [];
  }
  final progress = history.progresses[history.lastWatchEpisode];
  if (progress == null ||
      progress.episode != history.lastWatchEpisode ||
      progress.progress < Duration.zero) {
    return const [];
  }
  final identity = EpisodeIdentity(
      title: history.lastWatchEpisodeName, pageUrl: history.episodePageUrl);
  final choices = <CrossSourceResume>[];
  for (var road = 0; road < roads.length; road++) {
    final candidates = episodeIdentitiesForRoad(roads[road], baseUrl: baseUrl);
    final index =
        matchingEpisodeIdentity(identity, candidates, acrossSources: true);
    if (index == null) continue;
    choices.add(CrossSourceResume(
        bangumiId: bangumiId,
        pluginName: pluginName,
        src: src,
        road: road,
        episode: index + 1,
        episodePageUrl: candidates[index].pageUrl,
        offset: progress.progress.inSeconds));
  }
  return choices;
}
