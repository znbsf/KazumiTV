import 'package:flutter/material.dart';

import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/card/rule_card.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/utils/format.dart';

const Duration _kExpandDuration = Duration(milliseconds: 250);
const Curve _kExpandCurve = Curves.easeInOutCubic;

class DownloadRecordSliver extends StatelessWidget {
  const DownloadRecordSliver({
    super.key,
    required this.record,
    required this.expanded,
    required this.onToggle,
    required this.onResumeAll,
    required this.onDeleteAll,
    required this.totalSpeed,
    required this.episodeNumbers,
    required this.episodeTileBuilder,
  });

  final DownloadRecord record;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onResumeAll;
  final VoidCallback onDeleteAll;
  final double totalSpeed;

  final List<int> episodeNumbers;
  final Widget Function(BuildContext, int) episodeTileBuilder;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final episodes = record.episodes.values;
    final totalCount = episodes.length;
    var completedCount = 0;
    var activeCount = 0;
    var progressSum = 0.0;
    for (final episode in episodes) {
      final completed = episode.status == DownloadStatus.completed;
      if (completed) completedCount++;
      if (episode.status == DownloadStatus.downloading ||
          episode.status == DownloadStatus.resolving ||
          episode.status == DownloadStatus.pending) {
        activeCount++;
      }
      progressSum += completed ? 1.0 : episode.progressPercent;
    }
    final aggregateProgress = totalCount == 0 ? 0.0 : progressSum / totalCount;
    final allCompleted = completedCount >= totalCount;

    var meta = '$completedCount/$totalCount 已完成';
    if (activeCount > 0) {
      meta += ' · $activeCount 项进行中';
      if (totalSpeed > 0) {
        meta += ' · ${formatSpeed(totalSpeed)}';
      }
    }

    return SliverPadding(
      padding: const EdgeInsets.only(bottom: 12),
      sliver: DecoratedSliver(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        sliver: SliverMainAxisGroup(slivers: [
          SliverToBoxAdapter(
              child: Material(
                  type: MaterialType.transparency,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        onTap: onToggle,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              NetworkImgLayer(
                                src: record.bangumiCover,
                                width: 56,
                                height: 75,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      record.bangumiName,
                                      style: textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w700),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        RuleTag(
                                          label: record.pluginName,
                                          background:
                                              colorScheme.secondaryContainer,
                                          foreground:
                                              colorScheme.onSecondaryContainer,
                                        ),
                                        Text(
                                          meta,
                                          style: textTheme.bodySmall?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: Icon(
                                  Icons.more_vert,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                tooltip: '更多操作',
                                onSelected: (value) {
                                  if (value == 'resume_all') {
                                    onResumeAll();
                                  } else if (value == 'delete') {
                                    onDeleteAll();
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'resume_all',
                                    child: Text('全部开始'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text(
                                      '全部删除',
                                      style:
                                          TextStyle(color: colorScheme.error),
                                    ),
                                  ),
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: AnimatedRotation(
                                  turns: expanded ? 0.5 : 0,
                                  duration: _kExpandDuration,
                                  curve: _kExpandCurve,
                                  child: Icon(
                                    Icons.expand_more,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!allCompleted)
                        Padding(
                          padding:
                              EdgeInsets.fromLTRB(16, 0, 16, expanded ? 4 : 16),
                          child:
                              LinearProgressIndicator(value: aggregateProgress),
                        ),
                    ],
                  ))),
          if (expanded)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              sliver: SliverList.builder(
                itemCount: episodeNumbers.length,
                findChildIndexCallback: (key) {
                  if (key is! ValueKey<int>) return null;
                  final index = episodeNumbers.indexOf(key.value);
                  return index < 0 ? null : index;
                },
                itemBuilder: (context, index) => KeyedSubtree(
                  key: ValueKey(episodeNumbers[index]),
                  child: Material(
                    type: MaterialType.transparency,
                    child: episodeTileBuilder(context, episodeNumbers[index]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class DownloadEpisodeTile extends StatelessWidget {
  const DownloadEpisodeTile({
    super.key,
    required this.episode,
    required this.statusText,
    this.actions = const [],
    this.onPlay,
  });

  final DownloadEpisode episode;
  final String statusText;
  final List<Widget> actions;

  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isError = episode.status == DownloadStatus.failed;
    final showProgress = episode.status == DownloadStatus.downloading ||
        (episode.status == DownloadStatus.paused &&
            episode.progressPercent > 0);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onPlay,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            _EpisodeStatusBadge(episode: episode),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    episode.episodeName.isNotEmpty
                        ? episode.episodeName
                        : '第${episode.episodeNumber}集',
                    style: textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    statusText,
                    style: textTheme.bodySmall?.copyWith(
                      color: isError
                          ? colorScheme.error
                          : colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showProgress) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: episode.progressPercent),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            ...actions,
          ],
        ),
      ),
    );
  }
}

class _EpisodeStatusBadge extends StatelessWidget {
  const _EpisodeStatusBadge({required this.episode});

  final DownloadEpisode episode;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Color background;
    Widget child;
    switch (episode.status) {
      case DownloadStatus.completed:
        background = colorScheme.secondaryContainer;
        child = Icon(
          Icons.check_rounded,
          size: 18,
          color: colorScheme.onSecondaryContainer,
        );
        break;
      case DownloadStatus.downloading:
        background = Colors.transparent;
        child = SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            value: episode.progressPercent,
            strokeWidth: 2.5,
          ),
        );
        break;
      case DownloadStatus.resolving:
        background = Colors.transparent;
        child = const SizedBox(
          width: 22,
          height: 22,
          child: LoadingIndicator(),
        );
        break;
      case DownloadStatus.failed:
        background = colorScheme.errorContainer;
        child = Icon(
          Icons.error_outline_rounded,
          size: 18,
          color: colorScheme.onErrorContainer,
        );
        break;
      case DownloadStatus.paused:
        background = colorScheme.surfaceContainerHighest;
        child = Icon(
          Icons.pause_rounded,
          size: 18,
          color: colorScheme.onSurfaceVariant,
        );
        break;
      case DownloadStatus.pending:
      default:
        background = colorScheme.surfaceContainerHighest;
        child = Icon(
          Icons.schedule_rounded,
          size: 18,
          color: colorScheme.onSurfaceVariant,
        );
        break;
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Center(child: child),
    );
  }
}
