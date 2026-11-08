import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:scrollview_observer/scrollview_observer.dart';

class EpisodeCommentsPicker extends StatefulWidget {
  const EpisodeCommentsPicker({
    super.key,
    required this.episodes,
    required this.selectedEpisode,
  });

  final List<EpisodeInfo> episodes;
  final int selectedEpisode;

  @override
  State<EpisodeCommentsPicker> createState() => _EpisodeCommentsPickerState();
}

class _EpisodeCommentsPickerState extends State<EpisodeCommentsPicker> {
  final _scroll = ScrollController();
  late final _observer = ListObserverController(controller: _scroll);
  final _currentFocus = FocusNode(debugLabel: 'Current discussion episode');
  List<EpisodeInfo> get episodes => widget.episodes;
  int get selectedEpisode => widget.selectedEpisode;

  @override
  void initState() {
    super.initState();
    if (TvMode.enabled) {
      unawaited(_focusCurrent());
    }
  }

  Future<void> _focusCurrent() async {
    // Let ListViewObserver's first post-frame callback register the sliver.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || episodes.isEmpty || !_scroll.hasClients) return;
    final index = (selectedEpisode - 1).clamp(0, episodes.length - 1);
    final positioned = _observer.jumpTo(index: index);
    WidgetsBinding.instance.scheduleFrame();
    await positioned;
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _currentFocus.context == null) return;
      _currentFocus.requestFocus();
      Scrollable.ensureVisible(_currentFocus.context!);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _currentFocus.dispose();
    super.dispose();
  }

  Widget _observeEpisodes(Widget child) => TvMode.enabled
      ? ListViewObserver(controller: _observer, child: child)
      : child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final type = Theme.of(context).textTheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('选择讨论分集',
                      style: type.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('切换想看的讨论，视频会继续播放。',
                      style: type.bodyMedium
                          ?.copyWith(color: colors.onSurfaceVariant)),
                ],
              ),
            ),
            Flexible(
              child: _observeEpisodes(
                ListView.separated(
                  controller: TvMode.enabled ? _scroll : null,
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: episodes.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 3),
                  itemBuilder: (context, index) {
                    final info = episodes[index];
                    final title =
                        info.nameCn.isNotEmpty ? info.nameCn : info.name;
                    final selected = index + 1 == selectedEpisode;
                    return Material(
                      color: selected
                          ? colors.primaryContainer
                          : colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(index == 0 ? 20 : 4),
                        bottom: Radius.circular(
                            index == episodes.length - 1 ? 20 : 4),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        focusNode: TvMode.enabled &&
                                index ==
                                    (selectedEpisode - 1)
                                        .clamp(0, episodes.length - 1)
                            ? _currentFocus
                            : null,
                        selected: selected,
                        selectedColor: colors.onPrimaryContainer,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        title: Text(
                          '${info.readType().toUpperCase()} ${info.episode}'
                              .trim(),
                          style: type.labelLarge?.copyWith(
                            color: selected
                                ? colors.onPrimaryContainer
                                : colors.primary,
                          ),
                        ),
                        subtitle: title.isEmpty
                            ? null
                            : Text(title,
                                style: type.bodyLarge?.copyWith(
                                  color: selected
                                      ? colors.onPrimaryContainer
                                      : colors.onSurface,
                                )),
                        trailing: Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.chevron_right_rounded,
                          color: selected
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                        onTap: () => Navigator.pop(context, index + 1),
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
                  child: const Text('取消'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
