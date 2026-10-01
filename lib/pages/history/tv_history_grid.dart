import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/widget/tv_focus_navigation.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/bean/card/bangumi_history_card.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';

/// Remote grid; the parent retains the shared persistence and editing guards.
class TvHistoryGrid extends StatefulWidget {
  const TvHistoryGrid(
      {super.key,
      required this.entries,
      required this.editing,
      required this.onDelete});
  final List<History> entries;
  final bool editing;
  final Future<void> Function(History) onDelete;
  @override
  State<TvHistoryGrid> createState() => _TvHistoryGridState();
}

class _TvHistoryGridState extends State<TvHistoryGrid> with RouteAware {
  final _focusNodes = <String, FocusNode>{};
  final _emptyFocus = FocusNode(debugLabel: 'TV empty history back');
  final _scrollController = ScrollController();
  int _focusRequest = 0;
  int? _restoringRequest;
  int _columns = 1;
  PageRoute<void>? _route;
  bool _covered = false;
  bool _returnPending = false;
  ({
    String selected,
    String anchor,
    int anchorIndex,
    double offset
  })? _returnPosition;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_observeNavigation);
  }

  bool _observeNavigation(KeyEvent event) {
    // During a route transition the shell may still own the focus path. Observe
    // new navigation even then, without consuming it or touching another page.
    if (_restoringRequest != null &&
        TvMode.enabled &&
        _route?.isCurrent == true &&
        (event is KeyDownEvent || event is KeyRepeatEvent) &&
        const [
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.enter,
          LogicalKeyboardKey.select,
        ].contains(event.logicalKey)) {
      _cancelFocusRequest();
    }
    return false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<void> && route != _route) {
      rootRouteObserver.unsubscribe(this);
      _route = route;
      rootRouteObserver.subscribe(this, route);
    }
    _setCovered(
        RouteVisibility.isCoveredOf(context) || route?.isCurrent == false);
  }

  @override
  void didUpdateWidget(covariant TvHistoryGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.editing != oldWidget.editing) {
      _returnPosition = null;
      _returnPending = false;
      _cancelFocusRequest();
    }
  }

  @override
  void didPushNext() => _setCovered(true);

  @override
  void didPopNext() => _setCovered(false);

  void _setCovered(bool value) {
    if (_covered == value) return;
    _covered = value;
    _focusRequest++;
    if (value) {
      _returnPending = _returnPosition != null;
    } else if (_returnPending) {
      _returnPending = false;
      _restoreReturn(_focusRequest);
    }
  }

  void _rememberReturn(History history) {
    if (widget.editing || _covered || !_scrollController.hasClients) return;
    final items = widget.entries;
    if (items.isEmpty) return;
    final pixels = _scrollController.offset;
    final row = ((pixels - 4).clamp(0.0, double.infinity) / 152).floor();
    final anchor = (row * _columns).clamp(0, items.length - 1);
    _returnPosition = (
      selected: history.key,
      anchor: items[anchor].key,
      anchorIndex: anchor,
      offset: pixels - (4 + row * 152),
    );
  }

  bool _canRestore(int request) =>
      mounted &&
      TvMode.enabled &&
      !widget.editing &&
      !_covered &&
      request == _focusRequest &&
      ModalRoute.of(context)?.isCurrent == true;

  bool _attached(FocusNode node) =>
      node.context?.mounted == true && node.parent != null;

  Future<void> _restoreReturn(int request) async {
    final saved = _returnPosition;
    _returnPosition = null;
    if (saved == null) return;
    _restoringRequest = request;
    try {
      // The shell restores its content scope in the first return frame. Resolve
      // the updated list afterwards, without fighting that handoff.
      await WidgetsBinding.instance.endOfFrame;
      if (!_canRestore(request)) return;
      if (widget.entries.isEmpty) {
        if (_attached(_emptyFocus)) _emptyFocus.requestFocus();
        return;
      }
      final anchor =
          widget.entries.indexWhere((item) => item.key == saved.anchor);
      final fallback = anchor >= 0
          ? anchor
          : saved.anchorIndex.clamp(0, widget.entries.length - 1);
      if (_scrollController.hasClients) {
        final top = 4 + fallback ~/ _columns * 152.0;
        _scrollController.jumpTo((top + (anchor >= 0 ? saved.offset : 0))
            .clamp(0.0, _scrollController.position.maxScrollExtent));
        await WidgetsBinding.instance.endOfFrame;
      }
      // A stable selection and a viewport anchor are separate identities. Keep
      // the anchor when the selection remains visible; realize a moved selection
      // when necessary so Back never leaves an invisible remote target.
      for (var attempt = 0; attempt < 3 && _canRestore(request); attempt++) {
        final items = widget.entries;
        if (items.isEmpty) {
          if (_attached(_emptyFocus)) _emptyFocus.requestFocus();
          return;
        }
        final selected = items.indexWhere((item) => item.key == saved.selected);
        final currentAnchor =
            items.indexWhere((item) => item.key == saved.anchor);
        final index = selected >= 0
            ? selected
            : currentAnchor >= 0
                ? currentAnchor
                : saved.anchorIndex.clamp(0, items.length - 1);
        final node = _focusFor(items[index]);
        final top = 4 + index ~/ _columns * 152.0;
        final position =
            _scrollController.hasClients ? _scrollController.position : null;
        if (position != null &&
            (!_attached(node) ||
                top + 150 <= position.pixels ||
                top >= position.pixels + position.viewportDimension)) {
          _scrollController.jumpTo(top.clamp(0.0, position.maxScrollExtent));
          await WidgetsBinding.instance.endOfFrame;
          continue;
        }
        final current = FocusManager.instance.primaryFocus;
        final currentCard = current?.context
            ?.findAncestorWidgetOfExactType<BangumiHistoryCardV>();
        // The card's detail menu may already have restored its More action.
        // Keep that action when it still belongs to the selected history.
        if (currentCard?.historyItem.key == items[index].key &&
            current != null &&
            _attached(current)) {
          return;
        }
        if (_attached(node)) node.requestFocus();
        return;
      }
    } finally {
      if (_restoringRequest == request) _restoringRequest = null;
    }
  }

  void _cancelFocusRequest() {
    _focusRequest++;
    _restoringRequest = null;
    _returnPosition = null;
    _returnPending = false;
    // Cancel the old viewport motion too: otherwise a newer More focus can
    // remain logically selected while its card is scrolled off screen.
    if (_scrollController.hasClients &&
        _scrollController.position.isScrollingNotifier.value) {
      _scrollController.jumpTo(_scrollController.offset);
    }
  }

  Future<void> _focusHistory(int index, int columns) async {
    final node = _focusFor(widget.entries[index]);
    final origin = FocusManager.instance.primaryFocus;
    final originScope = origin?.enclosingScope;
    final request = ++_focusRequest;
    final rowTop = index ~/ columns * 152.0 + 4;
    if (_scrollController.hasClients &&
        (node.context == null ||
            rowTop < _scrollController.offset ||
            rowTop + 150 >
                _scrollController.offset +
                    _scrollController.position.viewportDimension)) {
      await _scrollController.animateTo(
          (index ~/ columns * 152.0)
              .clamp(0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut);
      await WidgetsBinding.instance.endOfFrame;
    }
    if (mounted &&
        node.context != null &&
        request == _focusRequest &&
        // A viewport eviction may detach the old node and choose a fallback.
        // An attached origin losing focus to another control is not that case.
        (FocusManager.instance.primaryFocus == origin ||
            origin?.parent == null) &&
        originScope?.hasFocus == true) {
      node.requestFocus();
    }
  }

  FocusNode _focusFor(History history) => _focusNodes.putIfAbsent(
      history.key, () => FocusNode(debugLabel: 'TV history ${history.key}'));

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_observeNavigation);
    rootRouteObserver.unsubscribe(this);
    _focusRequest++;
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _emptyFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _deleteHistory(History history, int index) async {
    await widget.onDelete(history);
    if (!mounted || !TvMode.enabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final items = widget.entries;
      if (items.isEmpty) {
        _emptyFocus.requestFocus();
      } else {
        _focusFor(items[index.clamp(0, items.length - 1)]).requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) => Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) _focusRequest++;
        return KeyEventResult.ignored;
      },
      child: renderBody);
  Widget get renderBody {
    if (widget.entries.isNotEmpty) {
      return contentGrid;
    } else {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const GeneralEmptyState(
            icon: Icons.history_rounded,
            title: '暂无历史记录',
          ),
          if (TvMode.enabled)
            TextButton.icon(
                autofocus: true,
                focusNode: _emptyFocus,
                onPressed: () {
                  if (Actions.maybeFind<TvFocusRailIntent>(context) != null) {
                    Actions.invoke(context, const TvFocusRailIntent());
                  } else {
                    Navigator.of(context).maybePop();
                  }
                },
                icon: const Icon(Icons.arrow_back),
                label: const Text('返回')),
        ]),
      );
    }
  }

  Widget get contentGrid {
    int crossCount = 1;
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.compact['width']!) {
      crossCount = 2;
    }
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.medium['width']!) {
      crossCount = 3;
    }

    final double screenWidth = MediaQuery.sizeOf(context).width;
    if (TvMode.enabled) {
      // Reserve the rail and enough room for poster, text and a separate More
      // target. The old three-column phone density truncates even short titles.
      crossCount = ((screenWidth - 80) / 380).floor().clamp(1, 3);
    }
    _columns = crossCount;
    final double maxContentWidth = 1000;
    final double horizontalPadding =
        screenWidth > maxContentWidth ? (screenWidth - maxContentWidth) / 2 : 0;

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        const SliverPadding(padding: EdgeInsets.only(top: 4)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              mainAxisSpacing: 2,
              crossAxisSpacing: StyleString.cardSpace,
              crossAxisCount: crossCount,
              // TV adds a 10 px focus inset around the unchanged 140 px card.
              mainAxisExtent: TvMode.enabled ? 150 : 140,
            ),
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int index) {
                final history = widget.entries[index];
                return BangumiHistoryCardV(
                  key: ValueKey(history.key),
                  historyItem: history,
                  focusNode: TvMode.enabled ? _focusFor(history) : null,
                  onNavigationInput:
                      TvMode.enabled ? _cancelFocusRequest : null,
                  onOpeningRoute:
                      TvMode.enabled ? () => _rememberReturn(history) : null,
                  onKeyEvent: (_, event) {
                    if (!TvMode.enabled ||
                        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
                      return KeyEventResult.ignored;
                    }
                    if (event.logicalKey != LogicalKeyboardKey.arrowDown) {
                      _focusRequest++;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                        index % crossCount == 0) {
                      Actions.maybeInvoke(context, const TvFocusRailIntent());
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      final target = tvGridTarget(index, widget.entries.length,
                          crossCount, TraversalDirection.down);
                      _focusHistory(target, crossCount);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  showDelete: widget.editing,
                  onDeleted: () => _deleteHistory(history, index),
                );
              },
              childCount: widget.entries.length,
              findChildIndexCallback: (key) {
                if (key is! ValueKey<String>) return null;
                final index =
                    widget.entries.indexWhere((item) => item.key == key.value);
                return index < 0 ? null : index;
              },
            ),
          ),
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
      ],
    );
  }
}
