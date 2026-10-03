import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/bean/widget/tv_artwork.dart';
import 'package:kazumi/bean/widget/tv_desktop_navigation.dart';
import 'package:kazumi/bean/widget/tv_focusable_surface.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/storage/storage.dart';

/// Read-only links into the existing Dart history. Selection opens details;
/// source/episode resume remains owned by the existing detail/history flow.
class TvRecentWatch extends StatefulWidget {
  const TvRecentWatch({
    super.key,
    required this.onOpen,
    required this.onNavigation,
  });
  final Future<void> Function(History, FocusNode) onOpen;
  final VoidCallback onNavigation;
  @override
  State<TvRecentWatch> createState() => _TvRecentWatchState();
  static List<History> items() {
    final seen = <int>{};
    return HistoryRepository()
        .getAllHistories()
        .where((h) => seen.add(h.bangumiItem.id))
        .take(2)
        .toList();
  }
}

class _TvRecentWatchState extends State<TvRecentWatch> {
  final _nodes = <int, FocusNode>{};
  final _returnUses = <FocusNode, int>{};
  Set<int> _visibleIds = {};
  bool _pruneScheduled = false;
  @override
  void dispose() {
    for (final n in _nodes.values) {
      n.dispose();
    }
    _returnUses.clear();
    super.dispose();
  }

  Future<void> _open(History entry, FocusNode node) async {
    tvArtworkController.select(entry.bangumiItem);
    // The home owns route/focus generations for both posters and recent links.
    // Keep the origin alive until that owner has finished its return request.
    _returnUses.update(node, (count) => count + 1, ifAbsent: () => 1);
    try {
      await widget.onOpen(entry, node);
    } finally {
      final uses = _returnUses[node] ?? 0;
      if (uses <= 1) {
        _returnUses.remove(node);
      } else {
        _returnUses[node] = uses - 1;
      }
      if (mounted) _schedulePrune();
    }
  }

  void _schedulePrune() {
    if (_pruneScheduled) return;
    _pruneScheduled = true;
    // Focus children detach during the rebuild; dispose their external nodes
    // only after that frame, and retain nodes used by a pending route return.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pruneScheduled = false;
      if (!mounted) return;
      final obsolete = _nodes.entries
          .where((entry) =>
              !_visibleIds.contains(entry.key) &&
              !_returnUses.containsKey(entry.value))
          .toList();
      for (final entry in obsolete) {
        _nodes.remove(entry.key);
        entry.value.dispose();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  KeyEventResult _handleNavigation(FocusNode node, KeyEvent event) {
    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.arrowRight ||
            event.logicalKey == LogicalKeyboardKey.arrowUp ||
            event.logicalKey == LogicalKeyboardKey.arrowDown)) {
      widget.onNavigation();
      // Menus and route returns explicitly request these nodes. That transfer
      // does not clear Flutter's directional history, so reversing an earlier
      // Up could pop this same recent node instead of entering the grid below.
      final scope = node.nearestScope;
      if (scope != null) {
        FocusTraversalGroup.maybeOfNode(node)?.invalidateScopeData(scope);
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Box<History>>(
        valueListenable: GStorage.histories.listenable(),
        builder: (context, _, child) {
          final entries = TvRecentWatch.items();
          _visibleIds = entries.map((entry) => entry.bangumiItem.id).toSet();
          _schedulePrune();
          if (entries.isEmpty) return const SizedBox.shrink();
          return SizedBox(
            height: 44,
            child: Row(
              children: [
                const Text('最近观看', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 12),
                for (final entry in entries)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: TvFocusableSurface(
                        key: ValueKey(entry.bangumiItem.id),
                        focusScale: 1,
                        borderRadius: 8,
                        onKeyEvent: _handleNavigation,
                        focusNode: TvDesktopNavigation.registerHomeFocus(
                          _nodes.putIfAbsent(
                            entry.bangumiItem.id,
                            () => FocusNode(
                              debugLabel: 'TV recent ${entry.bangumiItem.id}',
                            ),
                          ),
                          TvHomeFocusIdentity.recent(entry.bangumiItem.id),
                        ),
                        onFocusChange: (focused) {
                          if (focused)
                            tvArtworkController.select(entry.bangumiItem);
                        },
                        onPressed: () => unawaited(
                            _open(entry, _nodes[entry.bangumiItem.id]!)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          child: Text(
                            '${entry.bangumiItem.nameCn} · ${entry.lastWatchEpisodeName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );
}
