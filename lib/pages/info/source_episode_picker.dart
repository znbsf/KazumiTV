import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/widget/tv_focus_label.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
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
    if (TvMode.enabled) {
      return _TvSourceEpisodePicker(target: target, entries: entries);
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
                    child: Text('${target.roads[entry.road].name} · '
                        '${entry.identity.title} · 从头播放'),
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

typedef _Entry = ({int road, int episode, EpisodeIdentity identity});

class _TvSourceEpisodePicker extends StatefulWidget {
  const _TvSourceEpisodePicker({required this.target, required this.entries});
  final OnlineVideoPlaybackArgs target;
  final List<_Entry> entries;

  @override
  State<_TvSourceEpisodePicker> createState() => _TvSourceEpisodePickerState();
}

class _TvSourceEpisodePickerState extends State<_TvSourceEpisodePicker> {
  late final List<int> _roads;
  late final Map<int, List<_Entry>> _entries;
  late final Map<int, FocusNode> _roadFocus;
  late final Map<int, List<FocusNode>> _episodeFocus;
  int? _selectedRoad;
  bool _initialFocus = true;

  @override
  void initState() {
    super.initState();
    _roads = widget.entries.map((entry) => entry.road).toSet().toList();
    _entries = {
      for (final road in _roads)
        road: widget.entries.where((entry) => entry.road == road).toList(),
    };
    _roadFocus = {for (final road in _roads) road: FocusNode()};
    _episodeFocus = {
      for (final road in _roads)
        road: List.generate(_entries[road]!.length, (_) => FocusNode()),
    };
    _selectedRoad = _roads.isEmpty ? null : _roads.first;
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialFocus = false);
  }

  @override
  void dispose() {
    for (final node in _roadFocus.values) {
      node.dispose();
    }
    for (final nodes in _episodeFocus.values) {
      for (final node in nodes) {
        node.dispose();
      }
    }
    super.dispose();
  }

  void _reveal(BuildContext context, bool focused) {
    if (!focused) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        Scrollable.ensureVisible(context, duration: Duration.zero);
      }
    });
  }

  void _select(_Entry entry) {
    Navigator.pop(
        context,
        CrossSourceResume(
          bangumiId: widget.target.bangumiItem.id,
          pluginName: widget.target.plugin.name,
          src: widget.target.src,
          road: entry.road,
          episode: entry.episode,
          episodePageUrl: entry.identity.pageUrl,
          offset: 0,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final road = _selectedRoad;
    return AlertDialog(
      title: const Text('选择新源集数'),
      content: SizedBox(
        width: math.min(screen.width * .7, 820),
        height: math.max(0, screen.height - 240),
        child: road == null
            ? const Text('此结果没有可播放集数，请返回选择其他结果')
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_roads.length > 1) ...[
                    SizedBox(
                      width: 180,
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final item in _roads)
                              Builder(
                                builder: (rowContext) => Focus(
                                  canRequestFocus: false,
                                  onKeyEvent: (_, event) {
                                    if (event is! KeyDownEvent &&
                                        event is! KeyRepeatEvent) {
                                      return KeyEventResult.ignored;
                                    }
                                    final index = _roads.indexOf(item);
                                    if (event.logicalKey ==
                                        LogicalKeyboardKey.arrowRight) {
                                      _episodeFocus[item]!.first.requestFocus();
                                      return KeyEventResult.handled;
                                    }
                                    final delta = event.logicalKey ==
                                            LogicalKeyboardKey.arrowDown
                                        ? 1
                                        : event.logicalKey ==
                                                LogicalKeyboardKey.arrowUp
                                            ? -1
                                            : 0;
                                    if (delta != 0 &&
                                        index + delta >= 0 &&
                                        index + delta < _roads.length) {
                                      _roadFocus[_roads[index + delta]]!
                                          .requestFocus();
                                      return KeyEventResult.handled;
                                    }
                                    return KeyEventResult.ignored;
                                  },
                                  child: TextButton(
                                    key: ValueKey('source-road-$item'),
                                    focusNode: _roadFocus[item],
                                    style: TextButton.styleFrom(
                                      backgroundColor: _selectedRoad == item
                                          ? Theme.of(context)
                                              .colorScheme
                                              .secondaryContainer
                                          : null,
                                    ),
                                    onFocusChange: (focused) {
                                      _reveal(rowContext, focused);
                                      if (focused && _selectedRoad != item) {
                                        setState(() => _selectedRoad = item);
                                      }
                                    },
                                    onPressed: () {
                                      if (_selectedRoad != item) {
                                        setState(() => _selectedRoad = item);
                                      }
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                        if (mounted) {
                                          _episodeFocus[item]!
                                              .first
                                              .requestFocus();
                                        }
                                      });
                                    },
                                    child: Text(
                                      '${widget.target.roads[item].name} · '
                                      '${_entries[item]!.length}集',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: LayoutBuilder(builder: (context, constraints) {
                      final columns =
                          math.max(1, (constraints.maxWidth / 130).floor());
                      final tileWidth =
                          (constraints.maxWidth - (columns - 1) * 6) / columns;
                      final entries = _entries[road]!;
                      return SingleChildScrollView(
                        key: ValueKey('source-grid-$road'),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (var index = 0; index < entries.length; index++)
                              Builder(
                                builder: (tileContext) => SizedBox(
                                  width: tileWidth,
                                  child: Focus(
                                    canRequestFocus: false,
                                    onKeyEvent: (_, event) {
                                      if (event is! KeyDownEvent &&
                                          event is! KeyRepeatEvent) {
                                        return KeyEventResult.ignored;
                                      }
                                      final key = event.logicalKey;
                                      if (key == LogicalKeyboardKey.arrowLeft &&
                                          index % columns == 0 &&
                                          _roads.length > 1) {
                                        _roadFocus[road]!.requestFocus();
                                        return KeyEventResult.handled;
                                      }
                                      int? next;
                                      if (key == LogicalKeyboardKey.arrowLeft &&
                                          index % columns > 0) {
                                        next = index - 1;
                                      }
                                      if (key ==
                                              LogicalKeyboardKey.arrowRight &&
                                          index % columns < columns - 1) {
                                        next = index + 1;
                                      }
                                      if (key == LogicalKeyboardKey.arrowUp) {
                                        next = index - columns;
                                      }
                                      if (key == LogicalKeyboardKey.arrowDown) {
                                        next = index + columns;
                                      }
                                      if (next != null &&
                                          next >= 0 &&
                                          next < entries.length) {
                                        _episodeFocus[road]![next]
                                            .requestFocus();
                                        return KeyEventResult.handled;
                                      }
                                      return KeyEventResult.ignored;
                                    },
                                    child: TvFocusLabel(
                                      message: entries[index].identity.title,
                                      child: TextButton(
                                        key: ValueKey(
                                          'source-episode-$road-'
                                          '${entries[index].episode}',
                                        ),
                                        focusNode: _episodeFocus[road]![index],
                                        autofocus: _initialFocus &&
                                            road == _roads.first &&
                                            index == 0,
                                        onFocusChange: (focused) =>
                                            _reveal(tileContext, focused),
                                        onPressed: () =>
                                            _select(entries[index]),
                                        child: Text(
                                          entries[index].identity.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          autofocus: road == null,
          onPressed: () => Navigator.pop(context),
          child: const Text('返回选源'),
        )
      ],
    );
  }
}
