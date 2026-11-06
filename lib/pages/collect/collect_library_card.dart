part of 'collect_library_view.dart';

class _CollectLibraryCard extends StatefulWidget {
  const _CollectLibraryCard({
    super.key,
    required this.entry,
    required this.showRating,
    required this.onOpen,
    required this.onChangeType,
    this.focusNode,
  });

  final CollectedBangumi entry;
  final bool showRating;
  final VoidCallback onOpen;
  final ValueChanged<CollectType>? onChangeType;
  final FocusNode? focusNode;

  @override
  State<_CollectLibraryCard> createState() => _CollectLibraryCardState();
}

class _CollectLibraryCardState extends State<_CollectLibraryCard> {
  final _statusFocus = FocusNode(debugLabel: 'TV collection status');
  final _menuController = MenuController();
  final _menuFocusNodes = {
    for (final type in CollectType.values)
      type: FocusNode(debugLabel: 'TV library menu ${type.name}'),
  };
  LocalHistoryEntry? _menuHistory;
  bool _disposing = false;

  bool get _tvFocus => TvMode.enabled && widget.focusNode != null;

  void _onMenuOpen() {
    if (!_tvFocus) return;
    final route = ModalRoute.of(context);
    if (route != null && _menuHistory == null) {
      _menuHistory = LocalHistoryEntry(onRemove: () {
        _menuHistory = null;
        if (!_disposing && _menuController.isOpen) _menuController.close();
      });
      route.addLocalHistoryEntry(_menuHistory!);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_tvFocus ||
          !_menuController.isOpen ||
          widget.onChangeType == null) {
        return;
      }
      final current = CollectType.fromValue(widget.entry.type);
      // The checked item is disabled; start at the next available status.
      final statuses =
          CollectType.values.where((type) => type.isCollected).toList();
      final next = statuses[(statuses.indexOf(current) + 1) % statuses.length];
      _menuFocusNodes[next]!.requestFocus();
    });
  }

  void _onMenuClose() {
    final entry = _menuHistory;
    _menuHistory = null;
    entry?.remove();
    // The library's post-change restoration takes over if this card disappears.
    if (!_disposing && _tvFocus) _statusFocus.requestFocus();
  }

  @override
  void dispose() {
    _disposing = true;
    _menuHistory?.remove();
    _statusFocus.dispose();
    for (final node in _menuFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final item = widget.entry.bangumiItem;
    final title = CollectLibraryQuery.titleOf(widget.entry);
    final type = CollectType.fromValue(widget.entry.type);
    final airDate = DateTime.tryParse(item.airDate);
    final metadata = [
      if (airDate != null) '${airDate.year} 年',
      if (widget.showRating && item.ratingScore > 0)
        '${item.ratingScore.toStringAsFixed(1)} 分',
    ];

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Isolate menu focus and taps from card navigation.
          Positioned.fill(
            child: Semantics(
              button: true,
              label: [title, ...metadata].join('，'),
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: (_, event) {
                  if (_tvFocus &&
                      widget.onChangeType != null &&
                      widget.focusNode!.hasPrimaryFocus &&
                      event.logicalKey == LogicalKeyboardKey.arrowRight &&
                      (event is KeyDownEvent || event is KeyRepeatEvent)) {
                    _statusFocus.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child:
                    InkWell(focusNode: widget.focusNode, onTap: widget.onOpen),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: IgnorePointer(
                    child: Hero(
                      tag: item.id,
                      transitionOnUserGestures: true,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: NetworkImgLayer(
                          src: item.images['large'] ??
                              item.images['common'] ??
                              '',
                          width: 80,
                          height: 120,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExcludeSemantics(
                        child: IgnorePointer(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 76),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      height: 1.35,
                                    ),
                                  ),
                                  if (metadata.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        metadata.join('  ·  '),
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      _statusMenu(context, type, title),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (TvMode.enabled && widget.focusNode != null)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: widget.focusNode!,
                  builder: (context, _) => DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: widget.focusNode!.hasFocus
                            ? colors.primary
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusMenu(BuildContext context, CollectType type, String title) {
    final colors = Theme.of(context).colorScheme;
    const itemStyle = ButtonStyle(
      visualDensity: VisualDensity.standard,
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
      minimumSize: WidgetStatePropertyAll(Size(192, 48)),
    );

    return MenuAnchor(
      controller: _menuController,
      childFocusNode: _tvFocus ? _statusFocus : null,
      onOpen: _onMenuOpen,
      onClose: _onMenuClose,
      consumeOutsideTap: true,
      style: MenuStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      menuChildren: [
        for (final status
            in CollectType.values.where((type) => type.isCollected))
          MenuItemButton(
            focusNode: _tvFocus ? _menuFocusNodes[status] : null,
            style: itemStyle,
            trailingIcon:
                status == type ? const Icon(Icons.check_rounded) : null,
            onPressed: widget.onChangeType == null || status == type
                ? null
                : () => widget.onChangeType!(status),
            child: Text(status.label),
          ),
        const Divider(indent: 16, endIndent: 16),
        MenuItemButton(
          focusNode: _tvFocus ? _menuFocusNodes[CollectType.none] : null,
          style: itemStyle,
          onPressed: widget.onChangeType == null
              ? null
              : () => widget.onChangeType!(CollectType.none),
          child: TvButtonText('取消收藏', color: colors.error),
        ),
      ],
      builder: (context, controller, child) => Tooltip(
        message: '调整《$title》的观看状态',
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (_, event) {
            if (_tvFocus &&
                _statusFocus.hasPrimaryFocus &&
                event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                (event is KeyDownEvent || event is KeyRepeatEvent)) {
              widget.focusNode!.requestFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: FilledButton.tonalIcon(
            focusNode: _tvFocus ? _statusFocus : null,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.standard,
              tapTargetSize: MaterialTapTargetSize.padded,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 12, 0),
            ),
            onPressed: widget.onChangeType == null
                ? null
                : () =>
                    controller.isOpen ? controller.close() : controller.open(),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.expand_more_rounded, size: 18),
            label: Text(type.label),
          ),
        ),
      ),
    );
  }
}
