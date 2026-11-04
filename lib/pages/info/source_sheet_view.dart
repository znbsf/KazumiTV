part of 'source_sheet.dart';

/// Search snapshot shared by the source sheet's two presentations.
class SourceSearchGroup {
  const SourceSearchGroup({
    required this.name,
    required this.keyword,
    required this.status,
    required this.results,
    this.unsearched = false,
  });

  final String name;
  final String keyword;
  final PluginSearchStatus status;
  final List<SearchItem> results;
  final bool unsearched;

  bool get isSearching => !unsearched && status == PluginSearchStatus.pending;
  bool get hasResults =>
      status == PluginSearchStatus.success && results.isNotEmpty;

  String get statusLabel => unsearched
      ? '选择此来源搜索'
      : switch (status) {
          PluginSearchStatus.pending => '检索中…',
          PluginSearchStatus.success =>
            results.isEmpty ? '无结果' : '${results.length} 个结果',
          PluginSearchStatus.noResult => '无结果',
          PluginSearchStatus.error => '检索失败',
          PluginSearchStatus.captcha => '需要验证',
        };
}

enum _SourceDisplay { preview, expanded, collapsed }

/// Source selection presentation; searching and playback stay with SourceSheet.
class SourceSheetView extends StatefulWidget {
  const SourceSheetView({
    super.key,
    required this.keyword,
    required this.groups,
    required this.firstResultSource,
    required this.onSourceSearch,
    required this.onSourceAliasSearch,
    required this.onRetry,
    required this.onVerify,
    required this.onOpenBrowser,
    required this.onPlay,
    required this.onClose,
  });

  final String keyword;
  final List<SourceSearchGroup> groups;
  final String? firstResultSource;
  final ValueChanged<String> onSourceSearch;
  final ValueChanged<String> onSourceAliasSearch;
  final ValueChanged<String> onRetry;
  final ValueChanged<String> onVerify;
  final ValueChanged<String> onOpenBrowser;
  final void Function(String sourceName, SearchItem result) onPlay;
  final VoidCallback onClose;

  @override
  State<SourceSheetView> createState() => _SourceSheetViewState();
}

class _SourceSheetViewState extends State<SourceSheetView> {
  final _scrollController = ScrollController();
  final _display = <String, _SourceDisplay>{};
  final _headerKeys = <String, GlobalKey>{};
  final _headerFocus = <String, FocusNode>{};
  final _resultFocus = <(String, String), FocusNode>{};
  final _retiredResultFocus = <FocusNode>{};
  final _rightFocus = FocusNode(debugLabel: 'TV source content');
  String? _selectedSource;
  bool _autoExpansionHandled = false;

  @override
  void initState() {
    super.initState();
    _autoExpandFirstResult();
    _selectedSource =
        widget.firstResultSource ?? widget.groups.firstOrNull?.name;
    if (TvMode.enabled) {
      // One initial request only. Later responses must never take focus away
      // from the user's current source, result, menu or header control.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final group = _selectedGroup;
        if (group == null) return;
        if (group.hasResults) {
          _focusRight();
        } else {
          _focusHeader(group.name);
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant SourceSheetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final names = widget.groups.map((group) => group.name).toSet();
    _display.removeWhere((name, _) => !names.contains(name));
    _headerKeys.removeWhere((name, _) => !names.contains(name));
    if (!names.contains(_selectedSource)) {
      _selectedSource = widget.groups.firstOrNull?.name;
    }
    _autoExpandFirstResult();
    final resultKeys = {
      for (final group in widget.groups)
        for (final result in group.results) (group.name, result.src),
    };
    final retired = <FocusNode>[];
    _resultFocus.removeWhere((key, node) {
      if (resultKeys.contains(key)) return false;
      retired.add(node);
      return true;
    });
    if (retired.isNotEmpty) {
      _retiredResultFocus.addAll(retired);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Let the old Focus widgets detach before disposing their nodes.
        for (final node in retired) {
          if (_retiredResultFocus.remove(node)) node.dispose();
        }
      });
    }
    if (TvMode.enabled) {
      final focused = FocusManager.instance.primaryFocus;
      final belongsToView = _headerFocus.containsValue(focused) ||
          _resultFocus.containsValue(focused) ||
          (focused?.ancestors.contains(_rightFocus) ?? false);
      if (belongsToView && focused != null) {
        // Reordering or a taller status label can move an unchanged node.
        _reveal(focused);
      }
    }
  }

  void _autoExpandFirstResult() {
    final name = widget.firstResultSource;
    if (_autoExpansionHandled || name == null) return;
    _autoExpansionHandled = true;
    _display[name] = _SourceDisplay.preview;
  }

  @override
  void dispose() {
    for (final node in _headerFocus.values) {
      node.dispose();
    }
    for (final node in _resultFocus.values) {
      node.dispose();
    }
    for (final node in _retiredResultFocus) {
      node.dispose();
    }
    _retiredResultFocus.clear();
    _rightFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _setDisplay(String name, _SourceDisplay display) {
    setState(() {
      _autoExpansionHandled = true;
      _display[name] = display;
    });
  }

  void _collapseFromFooter(String name) {
    _focusHeader(name);
    final headerContext = _headerKeys[name]?.currentContext;
    if (headerContext != null) {
      // Anchor before shrinking, while the header is still laid out.
      Scrollable.ensureVisible(headerContext, alignment: 0);
    }
    _setDisplay(name, _SourceDisplay.collapsed);
  }

  void _focusHeader(String name) {
    if (TvMode.enabled) _focusAndReveal(_headerFocus[name]);
  }

  void _reveal(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _retiredResultFocus.contains(node)) return;
      final target = node.context;
      if (node.hasPrimaryFocus && target != null && target.mounted) {
        Scrollable.ensureVisible(target, duration: Duration.zero);
      }
    });
  }

  void _focusAndReveal(FocusNode? node) {
    if (node == null) return;
    node.requestFocus();
    _reveal(node);
  }

  void _retry(String name) {
    _sourceAction(name, widget.onRetry);
  }

  void _sourceAction(String name, ValueChanged<String> action) {
    _focusHeader(name);
    action(name);
  }

  SourceSearchGroup? get _selectedGroup {
    for (final group in widget.groups) {
      if (group.name == _selectedSource) return group;
    }
    return null;
  }

  FocusNode _sourceNode(String name) => _headerFocus.putIfAbsent(
      name, () => FocusNode(debugLabel: 'TV source $name'));

  FocusNode _resultNode(SourceSearchGroup group, SearchItem result) =>
      _resultFocus.putIfAbsent((group.name, result.src),
          () => FocusNode(debugLabel: 'TV result ${group.name} ${result.src}'));

  void _selectSource(String name) {
    if (_selectedSource != name) setState(() => _selectedSource = name);
  }

  void _focusRight() {
    final group = _selectedGroup;
    if (group != null && group.hasResults) {
      _focusAndReveal(_resultNode(group, group.results.first));
      return;
    }
    for (final node in _rightFocus.traversalDescendants) {
      if (node is! FocusScopeNode && node.canRequestFocus) {
        _focusAndReveal(node);
        return;
      }
    }
  }

  Widget _buildTvColumns() {
    final group = _selectedGroup;
    return Padding(
      key: const ValueKey('tv-source-columns'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 36,
            child: SingleChildScrollView(
              key: const ValueKey('tv-source-list'),
              primary: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final source in widget.groups) _buildTvSourceRow(source),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 64,
            child: Focus(
              focusNode: _rightFocus,
              canRequestFocus: false,
              onKeyEvent: (_, event) {
                if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
                    event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  if (_selectedSource case final name?) _focusHeader(name);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: SingleChildScrollView(
                key: ValueKey(('tv-source-content', group?.name)),
                primary: false,
                child: group == null
                    ? const SizedBox.shrink()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (group.keyword != widget.keyword)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text('检索词：${group.keyword}'),
                            ),
                          if (group.hasResults)
                            for (var i = 0; i < group.results.length; i++)
                              Padding(
                                key: ValueKey(group.results[i].src),
                                padding: const EdgeInsets.only(bottom: 4),
                                child: TvFocusableSurface(
                                  focusNode:
                                      _resultNode(group, group.results[i]),
                                  focusScale: 1,
                                  ensureVisibleOnFocus: false,
                                  onFocusChange: (focused) {
                                    if (focused) {
                                      _reveal(
                                          _resultNode(group, group.results[i]));
                                    }
                                  },
                                  onPressed: () => widget.onPlay(
                                      group.name, group.results[i]),
                                  onKeyEvent: (_, event) =>
                                      _tvResultKey(group, i, event),
                                  child: _buildResult(group, i),
                                ),
                              )
                          else
                            _buildSourceBody(group, showAll: true),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  KeyEventResult _tvResultKey(
      SourceSearchGroup group, int index, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final delta = event.logicalKey == LogicalKeyboardKey.arrowDown
        ? 1
        : event.logicalKey == LogicalKeyboardKey.arrowUp
            ? -1
            : 0;
    if (delta == 0) return KeyEventResult.ignored;
    final next = index + delta;
    if (next < 0) return KeyEventResult.ignored; // Allow reaching the header.
    if (next < group.results.length) {
      _focusAndReveal(_resultNode(group, group.results[next]));
    }
    return KeyEventResult.handled;
  }

  Widget _buildTvSourceRow(SourceSearchGroup group) {
    final node = _sourceNode(group.name);
    final theme = Theme.of(context);
    return TvSettingsMenuAnchor(
      key: ValueKey(group.name),
      menuChildren: [
        MenuItemButton(
          onPressed: () => _sourceAction(group.name, widget.onSourceSearch),
          child: const Text('修改此来源的检索词'),
        ),
        MenuItemButton(
          onPressed: () =>
              _sourceAction(group.name, widget.onSourceAliasSearch),
          child: const Text('使用别名检索此来源'),
        ),
        MenuItemButton(
          onPressed: () => _retry(group.name),
          child: const Text('重新检索此来源'),
        ),
        MenuItemButton(
          onPressed: () => _sourceAction(group.name, widget.onOpenBrowser),
          child: const Text('在浏览器中打开'),
        ),
      ],
      builder: (context, controller, child) {
        void openMenu() {
          _focusAndReveal(node);
          _selectSource(group.name);
          // Pointer activation can start on a result in the other column.
          // The menu must remember this source row as its return target.
          FocusManager.instance.applyFocusChangesIfNeeded();
          controller.open();
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: TvFocusableSurface(
            focusNode: node,
            focusScale: 1,
            ensureVisibleOnFocus: false,
            highlighted: group.name == _selectedSource,
            onPressed: openMenu,
            onFocusChange: (focused) {
              if (focused) {
                _selectSource(group.name);
                _reveal(node);
              }
            },
            onKeyEvent: (_, event) {
              if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                return KeyEventResult.ignored;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                _focusRight();
                return KeyEventResult.handled;
              }
              final delta = event.logicalKey == LogicalKeyboardKey.arrowDown
                  ? 1
                  : event.logicalKey == LogicalKeyboardKey.arrowUp
                      ? -1
                      : 0;
              if (delta == 0) return KeyEventResult.ignored;
              final next =
                  widget.groups.indexWhere((g) => g.name == group.name) + delta;
              if (next < 0) return KeyEventResult.ignored;
              if (next < widget.groups.length) {
                _focusAndReveal(_sourceNode(widget.groups[next].name));
              }
              return KeyEventResult.handled;
            },
            child: Material(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                canRequestFocus: false,
                onTap: openMenu,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(group.name, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(group.statusLabel,
                          style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _animateSize(Widget child) => MediaQuery.disableAnimationsOf(context)
      ? child
      : AnimatedSize(
          duration: splitListMotionDuration,
          curve: splitListMotionCurve,
          alignment: Alignment.topCenter,
          child: child,
        );

  @override
  Widget build(BuildContext context) {
    final pending = widget.groups.where((group) => group.isSearching).length;
    final resultCount = widget.groups
        .where((group) => group.hasResults)
        .fold(0, (sum, group) => sum + group.results.length);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          MaterialBottomSheetHeader(
            title: '播放来源',
            description: pending > 0
                ? '检索中 ${widget.groups.length - pending}/'
                    '${widget.groups.length} · $resultCount 个结果'
                : '${widget.groups.length} 个来源 · $resultCount 个结果',
            compact: true,
            onClose: widget.onClose,
          ),
          Expanded(
            child: TvMode.enabled && widget.groups.isNotEmpty
                ? _buildTvColumns()
                : Scrollbar(
                    controller: _scrollController,
                    child: CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        if (widget.groups.isEmpty)
                          const SliverToBoxAdapter(
                            child: GeneralEmptyState(
                              icon: Icons.extension_rounded,
                              title: '请先在规则管理中添加来源',
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            sliver: SliverList.builder(
                              itemCount: widget.groups.length,
                              findChildIndexCallback: (key) {
                                final index = widget.groups.indexWhere(
                                    (group) => ValueKey(group.name) == key);
                                return index < 0 ? null : index;
                              },
                              itemBuilder: (context, index) {
                                final group = widget.groups[index];
                                return Padding(
                                  key: ValueKey(group.name),
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _buildSourceGroup(group),
                                );
                              },
                            ),
                          ),
                        const SliverToBoxAdapter(
                          child:
                              SafeArea(top: false, child: SizedBox(height: 24)),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceGroup(SourceSearchGroup group) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final display = _display[group.name] ?? _SourceDisplay.collapsed;
    final collapsed = display == _SourceDisplay.collapsed;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : splitListMotionDuration;

    void toggle() => _setDisplay(group.name,
        collapsed ? _SourceDisplay.preview : _SourceDisplay.collapsed);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: _headerKeys.putIfAbsent(group.name, GlobalKey.new),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  button: true,
                  expanded: !collapsed,
                  label: '来源规则：${group.name}，${group.statusLabel}',
                  onTap: toggle,
                  excludeSemantics: true,
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      focusNode: TvMode.enabled
                          ? _headerFocus.putIfAbsent(
                              group.name,
                              () => FocusNode(
                                  debugLabel: 'TV source ${group.name}'))
                          : null,
                      borderRadius: BorderRadius.circular(16),
                      onTap: toggle,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                          child: Row(
                            children: [
                              Expanded(
                                  child: Text(
                                group.name,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              )),
                              const SizedBox(width: 8),
                              Text(
                                group.statusLabel,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 8),
                              AnimatedRotation(
                                turns: collapsed ? 0 : 0.5,
                                duration: duration,
                                curve: splitListMotionCurve,
                                child: Icon(Icons.expand_more_rounded,
                                    size: 20, color: colors.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _buildSourceMenu(group),
            ],
          ),
        ),
        if (!collapsed && group.keyword != widget.keyword)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              '检索词：${group.keyword}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        _animateSize(
          collapsed
              ? const SizedBox.shrink()
              : _buildSourceBody(group,
                  showAll: display == _SourceDisplay.expanded),
        ),
      ],
    );
  }

  Widget _buildSourceBody(SourceSearchGroup group, {required bool showAll}) {
    if (group.unsearched) {
      return Padding(
          padding: const EdgeInsets.all(12),
          child: TextButton.icon(
            onPressed: () => _retry(group.name),
            icon: const Icon(Icons.search),
            label: Text('搜索 ${group.name}'),
          ));
    }
    if (!group.hasResults) {
      return SplitListRow(
        topRadius: splitListOuterRadius,
        bottomRadius: splitListOuterRadius,
        child: switch (group.status) {
          PluginSearchStatus.pending => _buildSearching(),
          PluginSearchStatus.success ||
          PluginSearchStatus.noResult =>
            GeneralEmptyState(
              icon: Icons.search_off_rounded,
              title: '没有找到匹配结果',
              compact: true,
              actions: [
                StateActionButton.tonal(
                  onPressed: () =>
                      _sourceAction(group.name, widget.onSourceSearch),
                  text: '修改检索词',
                ),
                TextButton(
                  onPressed: () =>
                      _sourceAction(group.name, widget.onSourceAliasSearch),
                  child: const Text('使用别名'),
                ),
              ],
            ),
          PluginSearchStatus.captcha =>
            _buildSourceIssue(group.name, requiresVerification: true),
          PluginSearchStatus.error =>
            _buildSourceIssue(group.name, requiresVerification: false),
        },
      );
    }

    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final visibleCount = showAll ? group.results.length : 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < visibleCount; index++) ...[
          if (index > 0) const SizedBox(height: splitListRowGap),
          _buildResult(group, index),
        ],
        if (group.results.length > 1) ...[
          const SizedBox(height: splitListRowGap),
          SplitListRow(
            bottomRadius: splitListOuterRadius,
            onTap: () => showAll
                ? _collapseFromFooter(group.name)
                : _setDisplay(group.name, _SourceDisplay.expanded),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        showAll ? '收起全部条目' : '展开全部 ${group.results.length} 个结果',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: primary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      showAll
                          ? Icons.unfold_less_rounded
                          : Icons.expand_more_rounded,
                      size: 20,
                      color: primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSourceMenu(SourceSearchGroup group) => TooltipVisibility(
        visible: false,
        child: PopupMenuButton<VoidCallback>(
          tooltip: '${group.name} 的更多操作',
          icon: const Icon(Icons.more_horiz_rounded, size: 20),
          onSelected: (action) => action(),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: () => _sourceAction(group.name, widget.onSourceSearch),
              child: const Text('修改此来源的检索词'),
            ),
            PopupMenuItem(
              value: () =>
                  _sourceAction(group.name, widget.onSourceAliasSearch),
              child: const Text('使用别名检索此来源'),
            ),
            PopupMenuItem(
              value: () => _retry(group.name),
              child: const Text('重新检索此来源'),
            ),
            PopupMenuItem(
              value: () => widget.onOpenBrowser(group.name),
              child: const Text('在浏览器中打开'),
            ),
          ],
        ),
      );

  Widget _buildResult(SourceSearchGroup group, int index) {
    final theme = Theme.of(context);
    final result = group.results[index];
    return SplitListRow(
      topRadius: index == 0 ? splitListOuterRadius : splitListInnerRadius,
      bottomRadius: group.results.length == 1
          ? splitListOuterRadius
          : splitListInnerRadius,
      onTap: () => widget.onPlay(group.name, result),
      child: Semantics(
        button: true,
        label: '播放 ${result.name}，来源 ${group.name}',
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(result.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                      )),
                ),
                const SizedBox(width: 16),
                Icon(Icons.play_arrow_rounded,
                    color: theme.colorScheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearching() => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const LoadingIndicator(size: 20, semanticsLabel: '正在检索'),
              const SizedBox(width: 12),
              Expanded(
                  child: Text('正在检索…',
                      style: Theme.of(context).textTheme.bodyMedium)),
            ],
          ),
        ),
      );

  Widget _buildSourceIssue(String sourceName,
      {required bool requiresVerification}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (icon, title, hint, action, onAction) = requiresVerification
        ? (
            Icons.verified_user_outlined,
            '需要验证',
            '完成网站验证后继续检索。',
            '进行验证',
            () {
              _focusHeader(sourceName);
              widget.onVerify(sourceName);
            },
          )
        : (
            Icons.error_outline_rounded,
            '检索失败',
            '可以重试，或打开网站检查是否可用。',
            '重试',
            () => _retry(sourceName),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  icon,
                  size: 20,
                  color: requiresVerification
                      ? colors.onSurfaceVariant
                      : colors.error,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        )),
                    const SizedBox(height: 2),
                    Text(hint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        )),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.tonal(onPressed: onAction, child: Text(action)),
              TextButton(
                onPressed: () => widget.onOpenBrowser(sourceName),
                child: const Text('打开网站'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
