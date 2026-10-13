import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/services/player/cross_source_resume.dart';
import 'package:kazumi/services/player/episode_identity.dart';
import 'package:kazumi/services/video_source/video_source_service.dart';
import 'package:kazumi/utils/async_session.dart';

/// A live player snapshot, independent of persisted (possibly older) history.
class SourceSwitchOrigin {
  const SourceSwitchOrigin({required this.episode, required this.offset});
  final EpisodeIdentity? episode;
  final int offset;

  List<CrossSourceResume> choices(OnlineVideoPlaybackArgs target) {
    if (episode == null) return const [];
    final choices = <CrossSourceResume>[];
    for (var road = 0; road < target.roads.length; road++) {
      final episodes = episodeIdentitiesForRoad(target.roads[road],
          baseUrl: target.plugin.baseUrl);
      final index =
          matchingEpisodeIdentity(episode!, episodes, acrossSources: true);
      if (index == null) continue;
      choices.add(CrossSourceResume(
        bangumiId: target.bangumiItem.id,
        pluginName: target.plugin.name,
        src: target.src,
        road: road,
        episode: index + 1,
        episodePageUrl: episodes[index].pageUrl,
        offset: offset < 0 ? 0 : offset,
      ));
    }
    return choices;
  }
}

class PreparedSourceSwitch {
  const PreparedSourceSwitch(this.args, this.source);
  final OnlineVideoPlaybackArgs args;
  final VideoSource source;
}

/// Resolves without touching the active player, its controller, or history.
/// Cancellation and disposal reject late results even from a faulty resolver.
class SourceSwitchResolver {
  SourceSwitchResolver(this.service);
  final IVideoSourceService service;
  final _requests = AsyncSessionOwner();

  Future<PreparedSourceSwitch> prepare(OnlineVideoPlaybackArgs args) async {
    final transfer = args.transfer;
    if (transfer == null ||
        !transfer.matches(
          currentBangumiId: args.bangumiItem.id,
          currentPlugin: args.plugin.name,
          currentSrc: args.src,
          roads: args.roads,
          baseUrl: args.plugin.baseUrl,
        )) {
      throw const VideoSourceNotFoundException('请先选择有效集数');
    }
    final request = _requests.begin();
    final source = await service.resolve(transfer.episodePageUrl,
        useLegacyParser: args.plugin.useLegacyParser, offset: transfer.offset);
    if (request.isStale) throw const VideoSourceCancelledException();
    if (source.url.trim().isEmpty) {
      throw const VideoSourceNotFoundException();
    }
    return PreparedSourceSwitch(args, source);
  }

  void cancel() {
    _requests.cancel();
    service.cancel();
  }

  Future<void> dispose() async {
    _requests.close();
    service.cancel();
    await service.dispose();
  }
}
