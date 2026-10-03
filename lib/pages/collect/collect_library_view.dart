import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/pages/collect/collect_library_query.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

part 'collect_library_card.dart';

class CollectLibraryView extends StatefulWidget {
  const CollectLibraryView({
    super.key,
    required this.entries,
    required this.showRating,
    required this.onOpen,
    required this.onChangeType,
    required this.canEdit,
  });

  final List<CollectedBangumi> entries;
  final bool showRating;
  final FutureOr<void> Function(BangumiItem) onOpen;
  final void Function(BangumiItem, CollectType) onChangeType;
  final bool Function(BangumiItem) canEdit;

  @override
  State<CollectLibraryView> createState() => _CollectLibraryViewState();
}

class _CollectLibraryViewState extends State<CollectLibraryView> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _categoryScrollController = ScrollController(keepScrollOffset: false);
  final _categoryKeys = {
    for (final type in _categories) type: GlobalKey(),
  };
  final _scrollControllers = {
    for (final type in _categories) type: ScrollController(),
  };
  PageStorageBucket _resultsStorage = PageStorageBucket();
  CollectType? _selectedType = CollectType.watching;
  CollectSort _sort = CollectSort.recentlyChanged;
  String _query = '';
  final _itemFocus = <int, FocusNode>{};
  final _rowKeys = <int, GlobalKey>{};
  List<CollectedBangumi> _tvEntries = [];
  int _tvColumns = 1;
  int _returnEpoch = 0;
  bool _opening = false;
  double _rowExtent = 154;
  final _headerKey = GlobalKey();

  FocusNode _focusFor(int id) => _itemFocus.putIfAbsent(
      id, () => FocusNode(debugLabel: 'TV collection $id'));

  double? _rowTop(int index) {
    final first = index ~/ _tvColumns * _tvColumns;
    if (first >= _tvEntries.length) return null;
    final object = _rowKeys[_tvEntries[first].bangumiItem.id]
        ?.currentContext
        ?.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize) {
      return null;
    }
    return RenderAbstractViewport.of(object)
        .getOffsetToReveal(object, 0)
        .offset;
  }

  double? _rowHeight(int index) {
    final first = index ~/ _tvColumns * _tvColumns;
    if (first >= _tvEntries.length) return null;
    final object = _rowKeys[_tvEntries[first].bangumiItem.id]
        ?.currentContext
        ?.findRenderObject();
    return object is RenderBox && object.attached && object.hasSize
        ? object.size.height
        : null;
  }

  bool _canRestore(
          int epoch, CollectType? type, String query, CollectSort sort) =>
      mounted &&
      epoch == _returnEpoch &&
      type == _selectedType &&
      query == _query &&
      sort == _sort &&
      ModalRoute.of(context)?.isCurrent == true &&
      !RouteVisibility.isCoveredOf(context);

  bool _attached(FocusNode node) =>
      node.context?.mounted == true && node.parent != null;

  Future<void> _open(BangumiItem item) async {
    if (!TvMode.enabled) {
      await widget.onOpen(item);
      return;
    }
    if (_opening) return;
    final type = _selectedType;
    final query = _query;
    final sort = _sort;
    final scroll = _scrollControllers[type]!;
    if (!scroll.hasClients || _tvEntries.isEmpty) return;
    var anchorIndex = 0;
    for (var i = 0; i < _tvEntries.length; i += _tvColumns) {
      final top = _rowTop(i);
      final height = _rowHeight(i);
      if (top != null && height != null && top + height > scroll.offset) {
        anchorIndex = i;
        _rowExtent = height;
        break;
      }
    }
    final anchorId = _tvEntries[anchorIndex].bangumiItem.id;
    final offset = scroll.offset - (_rowTop(anchorIndex) ?? scroll.offset);
    final epoch = ++_returnEpoch;
    _opening = true;
    try {
      await widget.onOpen(item);
    } finally {
      _opening = false;
    }
    await WidgetsBinding.instance.endOfFrame;
    bool valid() => _canRestore(epoch, type, query, sort);
    if (!valid()) return;
    if (_tvEntries.isEmpty) {
      _focusSearch();
      return;
    }
    final anchor =
        _tvEntries.indexWhere((entry) => entry.bangumiItem.id == anchorId);
    final fallback =
        anchor >= 0 ? anchor : anchorIndex.clamp(0, _tvEntries.length - 1);
    await _realizeRow(fallback, anchor >= 0 ? offset : 0, scroll, valid);
    // Resolve again after each realization frame: the projection may change
    // while covered, and no old FocusNode is retained across that boundary.
    for (var attempt = 0; attempt < 3 && valid(); attempt++) {
      if (_tvEntries.isEmpty) {
        _focusSearch();
        return;
      }
      final selected =
          _tvEntries.indexWhere((entry) => entry.bangumiItem.id == item.id);
      final currentAnchor =
          _tvEntries.indexWhere((entry) => entry.bangumiItem.id == anchorId);
      final index = selected >= 0
          ? selected
          : currentAnchor >= 0
              ? currentAnchor
              : anchorIndex.clamp(0, _tvEntries.length - 1);
      final node = _focusFor(_tvEntries[index].bangumiItem.id);
      final top = _rowTop(index);
      final height = _rowHeight(index) ?? _rowExtent;
      if (!_attached(node) ||
          top == null ||
          top + height <= scroll.offset ||
          top >= scroll.offset + scroll.position.viewportDimension) {
        await _realizeRow(index, 0, scroll, valid);
        continue;
      }
      node.requestFocus();
      return;
    }
  }

  Future<void> _realizeRow(int index, double offset, ScrollController scroll,
      bool Function() valid) async {
    // Existing rows have variable height. Estimate from a mounted neighbor,
    // then correct using its render viewport; cap work and check ownership
    // before every jump instead of starting an uncancellable scrolling task.
    for (var attempt = 0;
        attempt < 3 && valid() && scroll.hasClients;
        attempt++) {
      if (_tvEntries.isEmpty) return;
      index = index.clamp(0, _tvEntries.length - 1);
      var top = _rowTop(index);
      if (top == null) {
        var distance = _tvEntries.length;
        for (var i = 0; i < _tvEntries.length; i += _tvColumns) {
          final known = _rowTop(i);
          if (known == null || (i - index).abs() >= distance) continue;
          distance = (i - index).abs();
          final extent = _rowHeight(i) ?? _rowExtent;
          top = known + (index ~/ _tvColumns - i ~/ _tvColumns) * extent;
        }
        final header = _headerKey.currentContext?.findRenderObject();
        top ??=
            (header is RenderBox && header.hasSize ? header.size.height : 0) +
                index ~/ _tvColumns * _rowExtent;
      }
      final target = (top + offset).clamp(0.0, scroll.position.maxScrollExtent);
      if (_rowTop(index) != null && (scroll.offset - target).abs() < 0.5) {
        return;
      }
      scroll.jumpTo(target);
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  static const _categories = <CollectType?>[
    null,
    CollectType.watching,
    CollectType.planToWatch,
    CollectType.watched,
    CollectType.onHold,
    CollectType.abandoned,
  ];

  @override
  void dispose() {
    _returnEpoch++;
    for (final node in _itemFocus.values) {
      node.dispose();
    }
    _searchController.dispose();
    _searchFocus.dispose();
    _categoryScrollController.dispose();
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _resetResults() {
    _returnEpoch++;
    // Reset stored offsets for unmounted categories too.
    _resultsStorage = PageStorageBucket();
    for (final controller in _scrollControllers.values) {
      if (controller.hasClients) controller.jumpTo(0);
    }
  }

  void _focusSearch() {
    final controller = _scrollControllers[_selectedType]!;
    if (controller.hasClients) controller.jumpTo(0);
    _searchFocus.requestFocus();
  }

  void _selectType(CollectType? type) {
    if (type == _selectedType) return;
    _returnEpoch++;
    setState(() => _selectedType = type);
  }

  void _search(String value) {
    setState(() {
      _query = value;
      _resetResults();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _search('');
  }

  @override
  Widget build(BuildContext context) {
    final query = CollectLibraryQuery(widget.entries, _query);
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final platform = Theme.of(context).platform;
    final mobile =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _focusSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            _focusSearch,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          _clearSearch();
          _searchFocus.unfocus();
        },
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent || event is KeyRepeatEvent) _returnEpoch++;
          return KeyEventResult.ignored;
        },
        child: PageStorage(
          bucket: _resultsStorage,
          child: LayoutBuilder(builder: (context, constraints) {
            final paged = !TvMode.enabled &&
                mobile &&
                MediaQuery.orientationOf(context) == Orientation.portrait;
            final contentWidth = constraints.maxWidth.clamp(0.0, 1560.0);
            final inset = (constraints.maxWidth - contentWidth) / 2 +
                (constraints.maxWidth < 600 ? 16.0 : 24.0);
            if (paged) {
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: inset),
                child: _pagedContent(query, textScale: textScale),
              );
            }
            final expanded = constraints.maxWidth >= 1000 && textScale <= 1.5;
            return Padding(
              padding: EdgeInsets.only(left: inset),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (expanded) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _sidebar(query),
                    ),
                    const SizedBox(width: 28),
                  ],
                  Expanded(
                    child: _scrollableContent(
                      query,
                      _selectedType,
                      textScale: textScale,
                      rightInset: inset,
                      header: _header(query, expanded: expanded),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _sidebar(CollectLibraryQuery query) {
    final theme = Theme.of(context);
    return SizedBox(
      key: const ValueKey('collect-sidebar'),
      width: 224,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Material(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
                  child: Text('收藏分类',
                      style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
                for (final type in _categories)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _category(type, query, wide: true),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchBar() => SearchBar(
        controller: _searchController,
        focusNode: _searchFocus,
        hintText: '搜索收藏番剧的名称、别名',
        leading: const Padding(
          padding: EdgeInsets.only(left: 8),
          child: Icon(Icons.search_rounded),
        ),
        trailing: [
          if (_query.isNotEmpty)
            IconButton(
              tooltip: '清除搜索',
              onPressed: _clearSearch,
              icon: const Icon(Icons.close_rounded),
            ),
        ],
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(
            Theme.of(context).colorScheme.surfaceContainerHigh),
        constraints: const BoxConstraints(minHeight: 56),
        onChanged: _search,
        onSubmitted: (_) => _searchFocus.unfocus(),
      );

  Widget _categoryStrip(CollectLibraryQuery query) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_categoryScrollController.hasClients) return;
      final target =
          _categoryKeys[_selectedType]?.currentContext?.findRenderObject();
      if (target == null) return;
      // Avoid scrolling the enclosing results list.
      _categoryScrollController.position.ensureVisible(
        target,
        alignment: 0.5,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    });
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SingleChildScrollView(
        key: const ValueKey('collect-filter-strip'),
        controller: _categoryScrollController,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final type in _categories)
              Padding(
                key: _categoryKeys[type],
                padding: const EdgeInsets.only(right: 8),
                child: _category(type, query),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header(CollectLibraryQuery query, {required bool expanded}) => Column(
        key: _headerKey,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(child: _searchBar()),
                const SizedBox(width: 8),
                _sortMenu(expanded: expanded),
              ],
            ),
          ),
          if (!expanded) _categoryStrip(query),
          const SizedBox(height: 16),
        ],
      );

  Widget _pagedContent(CollectLibraryQuery query, {required double textScale}) {
    return Column(
      children: [
        _header(query, expanded: false),
        Expanded(
          child: _CollectCategoryPager(
            selectedIndex: _categories.indexOf(_selectedType),
            onChanged: (index) {
              _searchFocus.unfocus();
              _selectType(_categories[index]);
            },
            itemCount: _categories.length,
            itemBuilder: (context, index) => HeroMode(
              // Avoid duplicate Hero tags across collection categories.
              enabled: _categories[index] == _selectedType,
              child: _scrollableContent(
                query,
                _categories[index],
                textScale: textScale,
                rightInset: 0,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _scrollableContent(
    CollectLibraryQuery query,
    CollectType? type, {
    required double textScale,
    required double rightInset,
    Widget? header,
  }) {
    final entries = query.results(type, _sort);
    final scrollController = _scrollControllers[type]!;
    return LayoutBuilder(builder: (context, constraints) {
      final contentWidth = constraints.maxWidth - rightInset;
      final columns = contentWidth >= 840 && textScale <= 1.3 ? 2 : 1;
      if (TvMode.enabled && type == _selectedType) {
        _tvEntries = entries;
        _tvColumns = columns;
      }
      return CustomScrollView(
        key: PageStorageKey('collect-results-${type?.value ?? 'all'}'),
        controller: scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          if (header != null) SliverToBoxAdapter(child: header),
          if (entries.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _emptyState(query.count(null), type: type),
            )
          else
            SliverPadding(
              padding: EdgeInsets.only(
                  bottom: 24 + MediaQuery.paddingOf(context).bottom),
              sliver: SliverList.builder(
                itemCount: (entries.length + columns - 1) ~/ columns,
                itemBuilder: (context, index) {
                  final first = index * columns;
                  return Padding(
                    key: TvMode.enabled
                        ? _rowKeys.putIfAbsent(
                            entries[first].bangumiItem.id, () => GlobalKey())
                        : null,
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _card(entries[first])),
                        if (columns == 2) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: first + 1 < entries.length
                                ? _card(entries[first + 1])
                                : const SizedBox(),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
        ]
            .map((sliver) => SliverPadding(
                  padding: EdgeInsets.only(right: rightInset),
                  sliver: sliver,
                ))
            .toList(),
      );
    });
  }

  Widget _card(CollectedBangumi entry) => _CollectLibraryCard(
        key: ValueKey('collect-${entry.bangumiItem.id}'),
        entry: entry,
        showRating: widget.showRating,
        focusNode: TvMode.enabled ? _focusFor(entry.bangumiItem.id) : null,
        onOpen: () => unawaited(_open(entry.bangumiItem)),
        onChangeType: widget.canEdit(entry.bangumiItem)
            ? (type) => widget.onChangeType(entry.bangumiItem, type)
            : null,
      );

  Widget _category(CollectType? type, CollectLibraryQuery query,
      {bool wide = false}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = type == _selectedType;
    final label = type?.label ?? '全部';
    final count = query.count(type);
    final foreground =
        selected ? colors.onPrimaryContainer : colors.onSurfaceVariant;

    return Semantics(
      selected: selected,
      liveRegion: selected,
      button: true,
      label: '$label，$count 部',
      excludeSemantics: true,
      onTap: () => _selectType(type),
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 250),
        curve: Curves.easeInOutCubicEmphasized,
        decoration: BoxDecoration(
          color: selected
              ? colors.primaryContainer
              : wide
                  ? colors.surfaceContainerLow
                  : colors.surfaceContainer,
          borderRadius: BorderRadius.circular(selected ? 20 : 12),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(selected ? 20 : 12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('collect-filter-${type?.value ?? 'all'}'),
            onTap: () => _selectType(type),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: wide ? 56 : 48),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    Icon(
                      switch (type) {
                        CollectType.watching =>
                          Icons.play_circle_outline_rounded,
                        CollectType.planToWatch =>
                          Icons.bookmark_border_rounded,
                        CollectType.onHold =>
                          Icons.pause_circle_outline_rounded,
                        CollectType.watched => Icons.task_alt_rounded,
                        CollectType.abandoned =>
                          Icons.remove_circle_outline_rounded,
                        _ => Icons.video_library_outlined,
                      },
                      size: 20,
                      color: foreground,
                    ),
                    const SizedBox(width: 10),
                    Text(label,
                        style: theme.textTheme.labelLarge?.copyWith(
                            color: foreground,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500)),
                    if (wide) const Spacer() else const SizedBox(width: 10),
                    Text('$count',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                        )),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sortMenu({required bool expanded}) {
    final style = ButtonStyle(
      foregroundColor: WidgetStatePropertyAll(
          Theme.of(context).colorScheme.onSurfaceVariant),
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
    );
    return MenuAnchor(
      consumeOutsideTap: true,
      menuChildren: [
        for (final sort in CollectSort.values)
          MenuItemButton(
            trailingIcon:
                _sort == sort ? const Icon(Icons.check_rounded) : null,
            onPressed: () {
              setState(() {
                _sort = sort;
                _resetResults();
              });
            },
            child: Text(sort.label),
          ),
      ],
      builder: (context, controller, child) {
        void toggleMenu() =>
            controller.isOpen ? controller.close() : controller.open();

        return Tooltip(
          message: '排序：${_sort.label}',
          child: expanded
              ? TextButton.icon(
                  style: style,
                  onPressed: toggleMenu,
                  icon: const Icon(Icons.sort_rounded, size: 20),
                  label: Text(_sort.label),
                )
              : IconButton(
                  style: style,
                  onPressed: toggleMenu,
                  icon: const Icon(Icons.sort_rounded, size: 20),
                ),
        );
      },
    );
  }

  Widget _emptyState(int matchCount, {required CollectType? type}) {
    final searching = _query.trim().isNotEmpty;
    final String title;

    if (searching) {
      title = matchCount > 0 ? '当前分类没有匹配的番剧' : '没有找到匹配的番剧';
    } else if (matchCount == 0) {
      title = '还没有收藏的番剧';
    } else {
      title = switch (type) {
        CollectType.watching => '还没有在追的番剧',
        CollectType.planToWatch => '还没有想看的番剧',
        CollectType.watched => '还没有看过的番剧',
        CollectType.onHold => '没有搁置的番剧',
        CollectType.abandoned => '没有弃追的番剧',
        _ => '还没有收藏的番剧',
      };
    }
    return GeneralEmptyState(
      icon: searching ? Icons.search_off_rounded : Icons.video_library_outlined,
      title: title,
    );
  }
}

class _CollectCategoryPager extends StatefulWidget {
  const _CollectCategoryPager({
    required this.selectedIndex,
    required this.onChanged,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<_CollectCategoryPager> createState() => _CollectCategoryPagerState();
}

class _CollectCategoryPagerState extends State<_CollectCategoryPager> {
  late final _controller = PageController(
    initialPage: widget.selectedIndex,
    keepPage: false,
  );

  @override
  void didUpdateWidget(covariant _CollectCategoryPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex &&
        _controller.hasClients &&
        _controller.page?.round() != widget.selectedIndex) {
      // Tab taps jump; swipe callbacks keep the current animation.
      _controller.jumpToPage(widget.selectedIndex);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageView.builder(
        key: const ValueKey('collect-category-pages'),
        controller: _controller,
        onPageChanged: widget.onChanged,
        itemCount: widget.itemCount,
        itemBuilder: widget.itemBuilder,
        scrollBehavior:
            ScrollConfiguration.of(context).copyWith(scrollbars: false),
      );
}
