import 'package:flutter/material.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/services/player/cross_source_resume.dart';
import 'package:kazumi/services/player/episode_identity.dart';

/// Explicit selection for unmatched/ambiguous labels; never borrows an index.
class SourceEpisodePicker extends StatelessWidget {
  const SourceEpisodePicker({super.key, required this.target});
  final OnlineVideoPlaybackArgs target;

  @override
  Widget build(BuildContext context) {
    final entries = <({int road, int episode, EpisodeIdentity identity})>[];
    for (var road = 0; road < target.roads.length; road++) {
      final identities = episodeIdentitiesForRoad(target.roads[road],
          baseUrl: target.plugin.baseUrl);
      for (var index = 0; index < identities.length; index++) {
        if (identities[index].pageUrl.isNotEmpty) {
          entries.add(
              (road: road, episode: index + 1, identity: identities[index]));
        }
      }
    }
    return AlertDialog(
      title: const Text('选择新源集数'),
      content: SizedBox(
        width: 440,
        height: 320,
        child: entries.isEmpty
            ? const Text('此结果没有可播放集数，请返回选择其他结果')
            : ListView.builder(
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return TextButton(
                    autofocus: index == 0,
                    onPressed: () => Navigator.pop(
                        context,
                        CrossSourceResume(
                          bangumiId: target.bangumiItem.id,
                          pluginName: target.plugin.name,
                          src: target.src,
                          road: entry.road,
                          episode: entry.episode,
                          episodePageUrl: entry.identity.pageUrl,
                          offset: 0,
                        )),
                    child: Text(
                        '${target.roads[entry.road].name} · ${entry.identity.title} · 从头播放'),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('返回选源'))
      ],
    );
  }
}
