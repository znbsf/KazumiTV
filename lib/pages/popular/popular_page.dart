import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/widget/bangumi_mirror_error_widget.dart';
import 'package:kazumi/bean/widget/custom_dropdown_menu.dart';
import 'package:kazumi/bean/widget/tv_focusable_surface.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/popular/popular_controller.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:kazumi/utils/device.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/platform/tv_channel_input.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/platform/tv_navigation.dart';
import 'package:kazumi/bean/widget/tv_focus_navigation.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';
import 'package:kazumi/bean/widget/tv_artwork.dart';
import 'package:kazumi/bean/widget/tv_desktop_navigation.dart';
import 'package:kazumi/bean/widget/tv_visuals.dart';
import 'package:kazumi/pages/popular/tv_recent_watch.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/services/performance/tv_input_lifecycle.dart';

class PopularPage extends StatefulWidget {
  const PopularPage({super.key, required this.controller});

  final PopularController controller;

  @override
  State<PopularPage> createState() => _PopularPageState();
}

class _PopularPageState extends State<PopularPage> {
  static const _channelInputDelay = Duration(milliseconds: 1800);
  static const _channelLookupTimeout = Duration(seconds: 10);
  static const _channelLookupPageLimit = 5;
  static const _tvToolbarHeight = 64.0;
  static const _gridPadding = 8.0;
  static const _loadingIndicatorHeight = 4.0;

  late final ScrollController scrollController;
  PopularController get popularController => widget.controller;

  // Key used to position the dropdown menu for the tag selector
  final GlobalKey selectorKey = GlobalKey();
  final Map<int, FocusNode> _channelFocusNodes = {};
  final Map<String, FocusNode> _tagFocusNodes = {};
  final _retryFocusNode = FocusNode(debugLabel: 'TV directory retry');
  int? _retryReturnId;
  Timer? _tagSelectionTimer;
  Timer? _channelCommitTimer;
  Future<void>? _channelLookupFuture;
  String _channelInput = '';
  int? _channelCandidate;
  bool _channelSearching = false;
  bool _channelLookupFailed = false;
  bool _channelLookupLimited = false;
  int _gridFocusRequest = 0;
  int? _pendingGridChannel;
  // Channel numbers are presentation; focus identity follows the subject.
  int _homeReturnEpoch = 0;
  int? _restoringHomeEpoch;
  bool _openingHome = false;
  bool _homeReadyReported = false;
  bool _homeReadyFrameScheduled = false;
  final _spotlight = ValueNotifier<BangumiItem?>(null);
  Timer? _summaryTimer;
  int _summaryRevision = 0;
  final _summaryCache = <int, String>{};
  StreamSubscription<dynamic>? _historySubscription;
  VoidCallback? _releaseProbeState;
  ModalRoute<dynamic>? _probeRoute;
  bool _probeCovered = false;
  int? _probeColumns;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TvInputLifecycle.enabled) return;
    _probeRoute = ModalRoute.of(context);
    _probeCovered = RouteVisibility.isCoveredOf(context);
    _releaseProbeState ??= TvInputLifecycle.registerPageState(
      this,
      isCurrent: () =>
          mounted && _probeRoute?.isCurrent == true && !_probeCovered,
      read: () => {
        'route': '/tab/popular/',
        'isCurrent': _probeRoute?.isCurrent,
        'covered': _probeCovered,
        'columns': _probeColumns,
        'listLength': _visibleBangumiList.length,
        'currentTag': popularController.currentTag,
        'canLoadMore': popularController.canLoadMore,
        'isLoadingMore': popularController.isLoadingMore,
        'canRetryLoad': popularController.canRetryLoad,
        'gridRequest': _gridFocusRequest,
        'pendingChannel': _pendingGridChannel,
        'pendingItemId': _pendingGridChannel != null &&
                _pendingGridChannel! > 0 &&
                _pendingGridChannel! <= _visibleBangumiList.length
            ? _visibleBangumiList[_pendingGridChannel! - 1].id
            : null,
        'scrollOffset':
            scrollController.hasClients ? scrollController.offset : null,
        'maxScrollExtent': scrollController.hasClients
            ? scrollController.position.maxScrollExtent
            : null,
        'scrollTraceEnabled': true,
      },
      readCatalogIds: () => _visibleBangumiList.map((item) => item.id).toList(),
    );
    TvInputLifecycle.checkpoint('home_visibility');
  }

  void _traceGrid(String kind, Map<String, Object?> fields, {KeyEvent? event}) {
    if (!TvInputLifecycle.active) return;
    TvInputLifecycle.trace(
        kind,
        {
          'request': _gridFocusRequest,
          'pendingChannel': _pendingGridChannel,
          'count': _visibleBangumiList.length,
          'columns': _probeColumns,
          'canLoadMore': popularController.canLoadMore,
          'isLoadingMore': popularController.isLoadingMore,
          ...fields,
        },
        inputEvent: event);
  }

  double get _recentExtent => TvRecentWatch.items().isEmpty ? 0 : 44;
  double get _pinnedExtent => _tvToolbarHeight + _recentExtent;
  double get _rowSpacing => TvMode.enabled
      ? (TvVisuals.fixedSurfaces ? 12 : 16)
      : StyleString.cardSpace - 2;
  double get _introExtent => TvMode.enabled
      ? MediaQuery.textScalerOf(context).scale(74) + _recentExtent
      : 0;

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController(
      initialScrollOffset: popularController.scrollOffset,
    );
    scrollController.addListener(scrollListener);
    tvChannelInputController.addListener(_handleChannelDigit);
    TvNavigation.homeRequests.addListener(_focusHome);
    if (TvMode.enabled) {
      _historySubscription = GStorage.histories.watch().listen((_) {
        if (mounted) setState(() {});
      });
    }
    if (popularController.trendList.isEmpty) {
      popularController.queryBangumiByTrend();
    }
    if (TvMode.enabled && popularController.trendList.isNotEmpty) {
      _setSpotlight(popularController.trendList.first);
    }
  }

  @override
  void dispose() {
    _releaseProbeState?.call();
    _homeReturnEpoch++;
    _gridFocusRequest++;
    scrollController.removeListener(scrollListener);
    tvChannelInputController.removeListener(_handleChannelDigit);
    TvNavigation.homeRequests.removeListener(_focusHome);
    _tagSelectionTimer?.cancel();
    _channelCommitTimer?.cancel();
    ++_summaryRevision;
    _summaryTimer?.cancel();
    _spotlight.dispose();
    _historySubscription?.cancel();
    for (final node in _channelFocusNodes.values) {
      node.dispose();
    }
    for (final node in _tagFocusNodes.values) {
      node.dispose();
    }
    _retryFocusNode.dispose();
    scrollController.dispose();
    super.dispose();
  }

  void scrollListener() {
    if (TvInputLifecycle.active) {
      TvInputLifecycle.scrollChanged('/tab/popular/', scrollController.offset);
    }
    popularController.scrollOffset = scrollController.offset;
    if (scrollController.position.pixels >=
            scrollController.position.maxScrollExtent - 200 &&
        !popularController.isLoadingMore &&
        popularController.canLoadMore) {
      KazumiLogger().i(
        'PopularPageController: Fetching next recommendation batch',
      );
      if (popularController.currentTag != '') {
        popularController.queryBangumiByTag();
      } else {
        popularController.queryBangumiByTrend();
      }
    }
  }

  void _setSpotlight(BangumiItem item) {
    _spotlight.value = item;
    tvArtworkController.select(item,
        imageUrl: NetworkImgLayer.tvListCoverUrl(item.images));
    final revision = ++_summaryRevision;
    _summaryTimer?.cancel();
    if (item.summary.isNotEmpty || _summaryCache.containsKey(item.id)) return;
    _summaryTimer = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted ||
          revision != _summaryRevision ||
          RouteVisibility.isCoveredOf(context)) return;
      final details = await BangumiApi.getBangumiInfoByID(item.id);
      if (!mounted ||
          revision != _summaryRevision ||
          _spotlight.value?.id != item.id ||
          RouteVisibility.isCoveredOf(context)) return;
      if (details != null) {
        _summaryCache[item.id] = details.summary;
        if (_summaryCache.length > 64)
          _summaryCache.remove(_summaryCache.keys.first);
        setState(() {});
      }
    });
  }

  bool _hasCurrentSpotlight(List<BangumiItem> items) {
    final id = _spotlight.value?.id;
    return id != null &&
        (items.any((item) => item.id == id) ||
            TvRecentWatch.items().any((entry) => entry.bangumiItem.id == id));
  }

  void _scheduleDefaultSpotlight(List<BangumiItem> items) {
    if (!TvMode.enabled || items.isEmpty || _hasCurrentSpotlight(items)) return;
    final tag = popularController.currentTag;
    final firstId = items.first.id;
    final epoch = _homeReturnEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !TvMode.enabled ||
          epoch != _homeReturnEpoch ||
          tag != popularController.currentTag ||
          _openingHome ||
          ModalRoute.of(context)?.isCurrent != true ||
          RouteVisibility.isCoveredOf(context)) return;
      final current = _visibleBangumiList;
      if (current.isEmpty ||
          current.first.id != firstId ||
          _hasCurrentSpotlight(current)) return;
      // A cold request arrives after initState. Match native's first-item
      // spotlight without changing the user's current navigation focus.
      _setSpotlight(current.first);
    });
  }

  void _focusHome() {
    if (!mounted || !TvMode.enabled) return;
    _homeReturnEpoch++;
    _cancelGridFocusRequest();
    _tagSelectionTimer?.cancel();
    if (scrollController.hasClients) scrollController.jumpTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_visibleBangumiList.isEmpty) return;
      final first = _focusNodeForChannel(1);
      if (_attached(first)) first.requestFocus();
    });
  }

  KeyEventResult _handleGridKey(
    int index,
    int count,
    int columns,
    KeyEvent event,
  ) {
    if (!TvMode.enabled ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    _homeReturnEpoch++;
    // Repeats and quick reversals advance from the last requested cell, even
    // while its row is still scrolling into view. New input owns the request.
    final currentIndex = (_pendingGridChannel ?? (index + 1)) - 1;
    if (TvInputLifecycle.active) {
      _traceGrid('key', {'index': index, 'currentIndex': currentIndex},
          event: event);
    }
    _cancelGridFocusRequest();
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
      LogicalKeyboardKey.arrowRight => TraversalDirection.right,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      _ => null,
    };
    if (direction == null) {
      if (TvInputLifecycle.active)
        _traceGrid('disposition', {'reason': 'ignored'}, event: event);
      return KeyEventResult.ignored;
    }
    if (direction == TraversalDirection.left && currentIndex % columns == 0) {
      if (TvInputLifecycle.active)
        _traceGrid('disposition', {'reason': 'rail'}, event: event);
      Actions.maybeInvoke(context, const TvFocusRailIntent());
      return KeyEventResult.handled;
    }
    if (direction == TraversalDirection.up && currentIndex < columns) {
      if (TvInputLifecycle.active)
        _traceGrid('disposition', {'reason': 'category'}, event: event);
      _focusNodeForTag(popularController.currentTag).requestFocus();
      return KeyEventResult.handled;
    }
    if (direction == TraversalDirection.down) {
      final nextRow = (currentIndex ~/ columns + 1) * columns;
      if (nextRow >= count) {
        unawaited(_loadNextGridRow(currentIndex + columns + 1,
            originChannel: currentIndex + 1));
      } else {
        // A shorter final row still has a real target, even when this column
        // has no cell there. Stop/loading applies only after the final row.
        unawaited(_focusGridChannel(
            (currentIndex + columns).clamp(0, count - 1) + 1));
      }
      return KeyEventResult.handled;
    }
    final target = tvGridTarget(currentIndex, count, columns, direction) + 1;
    unawaited(_focusGridChannel(target));
    return KeyEventResult.handled;
  }

  Future<void> _loadNextGridRow(int target,
      {required int originChannel}) async {
    if (TvInputLifecycle.active)
      _traceGrid(
          'load_begin', {'target': target, 'originChannel': originChannel});
    final epoch = _homeReturnEpoch;
    final origin = FocusManager.instance.primaryFocus;
    if (!popularController.canLoadMore || popularController.isLoadingMore) {
      if (TvInputLifecycle.active)
        _traceGrid('load_skip',
            {'target': target, 'canRetryLoad': popularController.canRetryLoad});
      if (!popularController.isLoadingMore && popularController.canRetryLoad) {
        await _focusRetryFooter(originChannel);
      }
      return;
    }
    if (popularController.currentTag.isEmpty) {
      await popularController.queryBangumiByTrend();
    } else {
      await popularController.queryBangumiByTag();
    }
    if (TvInputLifecycle.active)
      _traceGrid('load_end', {
        'target': target,
        'epochCurrent': epoch == _homeReturnEpoch,
        'originUnchanged': FocusManager.instance.primaryFocus == origin
      });
    if (!mounted ||
        epoch != _homeReturnEpoch ||
        FocusManager.instance.primaryFocus != origin ||
        RouteVisibility.isCoveredOf(context) ||
        target > _visibleBangumiList.length) return;
    await _focusGridChannel(target);
  }

  Future<void> _focusRetryFooter(int channel) async {
    if (!scrollController.hasClients ||
        channel < 1 ||
        channel > _visibleBangumiList.length) return;
    final epoch = _homeReturnEpoch;
    final request = _gridFocusRequest;
    final origin = FocusManager.instance.primaryFocus;
    final id = _visibleBangumiList[channel - 1].id;
    _pendingGridChannel = channel;
    await _scrollToListEnd();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || request != _gridFocusRequest) return;
    _pendingGridChannel = null;
    if (epoch != _homeReturnEpoch ||
        FocusManager.instance.primaryFocus != origin ||
        RouteVisibility.isCoveredOf(context) ||
        !popularController.canRetryLoad ||
        !_attached(_retryFocusNode)) return;
    _retryReturnId = id;
    _retryFocusNode.requestFocus();
  }

  Future<void> _returnFromRetry({bool retry = false}) async {
    final epoch = ++_homeReturnEpoch;
    final tag = popularController.currentTag;
    final origin = FocusManager.instance.primaryFocus;
    _cancelGridFocusRequest();
    final items = _visibleBangumiList;
    if (items.isEmpty || (retry && !popularController.canRetryLoad)) return;
    final previous = items.indexWhere((item) => item.id == _retryReturnId);
    final index = previous >= 0 ? previous : items.length - 1;
    await _scrollToChannel(index + 1, revealOnly: true);
    if (!mounted ||
        epoch != _homeReturnEpoch ||
        tag != popularController.currentTag ||
        FocusManager.instance.primaryFocus != origin ||
        RouteVisibility.isCoveredOf(context)) return;
    final card = _focusNodeForChannel(index + 1);
    if (!_attached(card)) return;
    card.requestFocus();
    await WidgetsBinding.instance.endOfFrame;
    if (!retry ||
        !mounted ||
        epoch != _homeReturnEpoch ||
        tag != popularController.currentTag ||
        !card.hasPrimaryFocus ||
        !popularController.canRetryLoad) return;
    if (tag.isEmpty) {
      await popularController.queryBangumiByTrend(type: 'retry');
    } else {
      await popularController.queryBangumiByTag(type: 'retry');
    }
  }

  KeyEventResult _handleRetryKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      unawaited(_returnFromRetry());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _homeReturnEpoch++;
      _cancelGridFocusRequest();
      Actions.maybeInvoke(context, const TvFocusRailIntent());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _cancelGridFocusRequest() {
    if (TvInputLifecycle.active) _traceGrid('cancel', {});
    _gridFocusRequest++;
    if (_pendingGridChannel != null && scrollController.hasClients) {
      scrollController.jumpTo(scrollController.offset);
    }
    _pendingGridChannel = null;
  }

  Future<void> _focusGridChannel(int channelNumber) async {
    final request = _gridFocusRequest;
    final origin = FocusManager.instance.primaryFocus;
    final originScope = origin?.enclosingScope;
    _pendingGridChannel = channelNumber;
    if (TvInputLifecycle.active)
      _traceGrid('focus_begin', {'target': channelNumber});
    // A cached/kept-alive FocusNode can have a context outside the viewport.
    // Reveal by grid geometry first, in either direction, then transfer focus.
    await _scrollToChannel(channelNumber, revealOnly: true);
    if (!mounted || request != _gridFocusRequest) {
      if (TvInputLifecycle.active)
        _traceGrid('focus_abort', {
          'target': channelNumber,
          'originalRequest': request,
          'reason': !mounted ? 'unmounted' : 'request_superseded'
        });
      return;
    }
    _pendingGridChannel = null;
    // Large jumps can evict the old card and leave a fallback focus in this
    // scope. That is not a user's move to another control or covered route.
    if ((FocusManager.instance.primaryFocus != origin &&
            origin?.parent != null) ||
        originScope?.hasFocus != true) {
      if (TvInputLifecycle.active)
        _traceGrid('focus_abort', {
          'target': channelNumber,
          'reason': originScope?.hasFocus != true
              ? 'origin_scope_lost'
              : 'origin_changed_attached'
        });
      return;
    }
    if (channelNumber < 1 || channelNumber > _visibleBangumiList.length) {
      if (TvInputLifecycle.active)
        _traceGrid(
            'focus_abort', {'target': channelNumber, 'reason': 'out_of_range'});
      return;
    }
    final node = _focusNodeForChannel(channelNumber);
    if (TvInputLifecycle.active)
      _traceGrid(node.context != null ? 'focus_apply' : 'focus_abort', {
        'target': channelNumber,
        'targetItemId': _visibleBangumiList[channelNumber - 1].id,
        if (node.context == null) 'reason': 'target_context_missing'
      });
    if (node.context != null) node.requestFocus();
  }

  void _onChannelFocusChanged(int channelNumber, bool focused) {
    if (TvInputLifecycle.active)
      _traceGrid(
          'card_focus', {'channelNumber': channelNumber, 'focused': focused});
    if (focused && channelNumber <= _visibleBangumiList.length) {
      _setSpotlight(_visibleBangumiList[channelNumber - 1]);
    }
    if (!focused ||
        _pendingGridChannel != null ||
        _restoringHomeEpoch != null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _pendingGridChannel != null ||
          _restoringHomeEpoch != null ||
          channelNumber < 1 ||
          channelNumber > _visibleBangumiList.length ||
          !_focusNodeForChannel(channelNumber).hasPrimaryFocus) {
        return;
      }
      // Also cover focus restored by the rail or a popped detail route. During
      // a requested scroll, recycled-card fallback focus must not scroll us.
      _cancelGridFocusRequest();
      unawaited(_focusGridChannel(channelNumber));
    });
  }

  List<BangumiItem> get _visibleBangumiList =>
      popularController.currentTag == ''
          ? popularController.trendList
          : popularController.bangumiList;

  FocusNode _focusNodeForChannel(int channelNumber) {
    final id = _visibleBangumiList[channelNumber - 1].id;
    final node = _channelFocusNodes.putIfAbsent(id, () => FocusNode());
    node.debugLabel = 'TV channel $channelNumber';
    return TvDesktopNavigation.registerHomeFocus(
      node,
      TvHomeFocusIdentity.poster(subjectId: id, channelNumber: channelNumber),
    );
  }

  bool _attached(FocusNode node) =>
      node.context?.mounted == true && node.parent != null;

  FocusNode _focusNodeForTag(String tag) =>
      TvDesktopNavigation.registerHomeFocus(
        _tagFocusNodes.putIfAbsent(
          tag,
          () => FocusNode(
              debugLabel: 'TV category ${tag.isEmpty ? '热门番组' : tag}'),
        ),
        TvHomeFocusIdentity.category(tag),
      );

  void _handleChannelDigit() {
    final event = tvChannelInputController.value;
    if (!mounted || !TvMode.enabled) return;
    if (event != null) _homeReturnEpoch++;
    _cancelGridFocusRequest();
    if (event == null) {
      if (_channelInput.isNotEmpty || _channelSearching) {
        _clearChannelInput(notifyController: false);
      }
      return;
    }

    final nextInput = _channelInput.length >= 3
        ? '${event.digit}'
        : '$_channelInput${event.digit}';
    final channelNumber = int.tryParse(nextInput) ?? 0;
    _channelCommitTimer?.cancel();
    setState(() {
      _channelInput = nextInput;
      _channelCandidate = channelNumber;
      _channelSearching = channelNumber > _visibleBangumiList.length;
      _channelLookupFailed = false;
      _channelLookupLimited = false;
    });
    _channelLookupFuture = _previewChannel(channelNumber, nextInput);
    unawaited(_channelLookupFuture);
    _channelCommitTimer = Timer(
      _channelInputDelay,
      () => unawaited(_commitChannel(nextInput)),
    );
  }

  Future<void> _previewChannel(int channelNumber, String expectedInput) async {
    await _ensureChannelAvailable(channelNumber, expectedInput);
    if (!mounted || _channelInput != expectedInput) return;
    setState(() => _channelSearching = false);
    final itemCount = _visibleBangumiList.length;
    if (channelNumber < 1 || channelNumber > itemCount) {
      await _scrollToListEnd();
      return;
    }

    await _scrollToChannel(channelNumber);
    if (!mounted || _channelInput != expectedInput) return;
    if (channelNumber <= _visibleBangumiList.length) {
      _focusNodeForChannel(channelNumber).requestFocus();
    }
  }

  Future<void> _ensureChannelAvailable(
    int channelNumber,
    String expectedInput,
  ) async {
    final deadline = DateTime.now().add(_channelLookupTimeout);
    var loadedPages = 0;
    while (mounted &&
        _channelInput == expectedInput &&
        channelNumber > _visibleBangumiList.length) {
      if (loadedPages >= _channelLookupPageLimit ||
          !DateTime.now().isBefore(deadline)) {
        _channelLookupLimited = true;
        break;
      }
      if (popularController.isLoadingMore) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        continue;
      }

      final previousCount = _visibleBangumiList.length;
      try {
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) {
          _channelLookupLimited = true;
          break;
        }
        if (popularController.currentTag == '') {
          await popularController.queryBangumiByTrend().timeout(remaining);
        } else {
          await popularController.queryBangumiByTag().timeout(remaining);
        }
        loadedPages += 1;
      } on TimeoutException {
        if (mounted && _channelInput == expectedInput) {
          _channelLookupLimited = true;
        }
        break;
      } catch (error, stackTrace) {
        KazumiLogger().e(
          'PopularPage: channel number lookup failed',
          error: error,
          stackTrace: stackTrace,
        );
        if (mounted && _channelInput == expectedInput) {
          _channelLookupFailed = true;
        }
        break;
      }
      if (_visibleBangumiList.length <= previousCount) {
        break;
      }
    }
  }

  Future<void> _commitChannel(String expectedInput) async {
    if (!mounted || _channelInput != expectedInput) return;
    await _channelLookupFuture;
    if (!mounted || _channelInput != expectedInput) return;
    final channelNumber = int.tryParse(expectedInput) ?? 0;
    final items = _visibleBangumiList;
    if (channelNumber >= 1 && channelNumber <= items.length) {
      _clearChannelInput();
      unawaited(_openChannel(items[channelNumber - 1]));
      return;
    }

    if (_channelLookupFailed) {
      _clearChannelInput();
      KazumiDialog.showToast(
        message: '加载更多节目失败，无法确认 $channelNumber 号是否存在',
        context: context,
      );
      return;
    }
    if (_channelLookupLimited) {
      await _scrollToListEnd();
      if (!mounted) return;
      final currentCount = _visibleBangumiList.length;
      _clearChannelInput();
      KazumiDialog.showToast(
        message: '暂未加载到 $channelNumber 号，已在 5 页/10 秒处停止（当前 $currentCount 个）',
        context: context,
      );
      return;
    }

    await _scrollToListEnd();
    if (!mounted) return;
    final currentCount = _visibleBangumiList.length;
    _clearChannelInput();
    KazumiDialog.showToast(
      message: currentCount == 0
          ? '当前没有可选节目'
          : '没有 $channelNumber 号节目，已到列表末尾（当前 $currentCount 个）',
      context: context,
    );
  }

  void _clearChannelInput({bool notifyController = true}) {
    _channelCommitTimer?.cancel();
    _channelCommitTimer = null;
    if (mounted) {
      setState(() {
        _channelInput = '';
        _channelCandidate = null;
        _channelSearching = false;
        _channelLookupFailed = false;
        _channelLookupLimited = false;
      });
    }
    if (notifyController && tvChannelInputController.value != null) {
      tvChannelInputController.cancel();
    }
  }

  void _onRecentNavigation() {
    _homeReturnEpoch++;
    _cancelGridFocusRequest();
    _tagSelectionTimer?.cancel();
  }

  Future<void> _openRecent(History entry, FocusNode origin) =>
      _openHomeDetail(entry.bangumiItem, recentOrigin: origin);

  Future<void> _openChannel(BangumiItem item) => _openHomeDetail(item);

  Future<void> _openHomeDetail(BangumiItem item,
      {FocusNode? recentOrigin}) async {
    if (TvInputLifecycle.active)
      _traceGrid('detail_activate',
          {'itemId': item.id, 'alreadyOpening': _openingHome});
    if (_openingHome) return;
    _cancelGridFocusRequest();
    _clearChannelInput();
    if (!TvMode.enabled ||
        !scrollController.hasClients ||
        (_visibleBangumiList.isEmpty && recentOrigin == null)) {
      await context.pushNamed('/info/', arguments: item);
      return;
    }
    final columns = _gridCrossCount();
    final stride = _gridItemExtent(columns) + _rowSpacing;
    final pixels = scrollController.offset;
    final row = ((pixels -
                    _introExtent +
                    StyleString.cardSpace -
                    2 -
                    _loadingIndicatorHeight -
                    _gridPadding)
                .clamp(0.0, double.infinity) /
            stride)
        .floor();
    final anchorIndex = _visibleBangumiList.isEmpty
        ? 0
        : (row * columns).clamp(0, _visibleBangumiList.length - 1);
    final anchorId = _visibleBangumiList.isEmpty
        ? null
        : _visibleBangumiList[anchorIndex].id;
    final savedOffset = pixels - _introExtent - row * stride;
    final recentScope = recentOrigin?.enclosingScope;
    final recentIndex = TvRecentWatch.items()
        .indexWhere((entry) => entry.bangumiItem.id == item.id);
    final tag = popularController.currentTag;
    final epoch = ++_homeReturnEpoch;
    _restoringHomeEpoch = epoch;
    _openingHome = true;
    ++_summaryRevision;
    _summaryTimer?.cancel();
    bool current() =>
        mounted &&
        TvMode.enabled &&
        epoch == _homeReturnEpoch &&
        tag == popularController.currentTag &&
        ModalRoute.of(context)?.isCurrent == true &&
        !RouteVisibility.isCoveredOf(context);
    try {
      try {
        await context.pushNamed('/info/', arguments: item);
      } finally {
        _openingHome = false;
        if (TvInputLifecycle.active)
          _traceGrid('detail_return', {'itemId': item.id});
      }
      await WidgetsBinding.instance.endOfFrame;
      if (!current()) return;
      if (_visibleBangumiList.isNotEmpty) {
        final anchor = _visibleBangumiList.indexWhere(
          (value) => value.id == anchorId,
        );
        final fallback = anchor >= 0
            ? anchor
            : anchorIndex.clamp(0, _visibleBangumiList.length - 1);
        final newColumns = _gridCrossCount();
        final newStride = _gridItemExtent(newColumns) + _rowSpacing;
        if (scrollController.hasClients) {
          scrollController.jumpTo(
            (_introExtent +
                    fallback ~/ newColumns * newStride +
                    (anchor >= 0 ? savedOffset : 0))
                .clamp(0.0, scrollController.position.maxScrollExtent),
          );
          await WidgetsBinding.instance.endOfFrame;
        }
      }
      if (!current()) return;
      if (recentOrigin != null) {
        final recent = TvRecentWatch.items();
        if (recent.isNotEmpty) {
          final selected =
              recent.indexWhere((entry) => entry.bangumiItem.id == item.id);
          final index = selected >= 0
              ? selected
              : recentIndex.clamp(0, recent.length - 1);
          final id = recent[index].bangumiItem.id;
          for (final node
              in recentScope?.traversalDescendants ?? const <FocusNode>[]) {
            final identity = TvDesktopNavigation.homeFocusOf(node);
            if (identity?.kind == TvHomeFocusKind.recent &&
                identity?.subjectId == id &&
                _attached(node)) {
              node.requestFocus();
              return;
            }
          }
        }
        final category = _focusNodeForTag(tag);
        if (_attached(category)) category.requestFocus();
        return;
      }
      if (_visibleBangumiList.isEmpty) {
        final category = _focusNodeForTag(tag);
        if (_attached(category)) category.requestFocus();
        return;
      }
      for (var attempt = 0; attempt < 3 && current(); attempt++) {
        final items = _visibleBangumiList;
        if (items.isEmpty) {
          final category = _focusNodeForTag(tag);
          if (_attached(category)) category.requestFocus();
          return;
        }
        final selected = items.indexWhere((value) => value.id == item.id);
        final currentAnchor = items.indexWhere((value) => value.id == anchorId);
        final index = selected >= 0
            ? selected
            : currentAnchor >= 0
                ? currentAnchor
                : anchorIndex.clamp(0, items.length - 1);
        final node = _focusNodeForChannel(index + 1);
        final count = _gridCrossCount();
        final extent = _gridItemExtent(count);
        final rowOffset = index ~/ count * (extent + _rowSpacing);
        if (scrollController.hasClients) {
          if (!mounted) return;
          final header = _pinnedExtent + MediaQuery.paddingOf(context).top;
          final top = header +
              (_introExtent - _recentExtent) +
              _loadingIndicatorHeight +
              _gridPadding +
              rowOffset;
          final position = scrollController.position;
          if (!_attached(node) ||
              top + extent <= position.pixels + header ||
              top >= position.pixels + position.viewportDimension) {
            scrollController.jumpTo(
              (_introExtent + rowOffset).clamp(0.0, position.maxScrollExtent),
            );
            await WidgetsBinding.instance.endOfFrame;
            continue;
          }
        }
        if (_attached(node)) node.requestFocus();
        return;
      }
    } finally {
      if (_restoringHomeEpoch == epoch) _restoringHomeEpoch = null;
    }
  }

  int _gridCrossCount() {
    var crossCount = 3;
    final width = MediaQuery.sizeOf(context).width;
    if (width > LayoutBreakpoint.compact['width']!) {
      crossCount = 5;
    }
    if (width > LayoutBreakpoint.medium['width']!) {
      crossCount = TvMode.enabled && TvVisuals.fixedSurfaces ? 5 : 6;
    }
    if (TvInputLifecycle.enabled) _probeColumns = crossCount;
    return crossCount;
  }

  double _gridItemExtent(int crossCount) {
    if (TvMode.enabled) {
      final available = MediaQuery.sizeOf(context).height -
          MediaQuery.paddingOf(context).vertical -
          _tvToolbarHeight -
          _introExtent -
          _loadingIndicatorHeight -
          2 * _gridPadding -
          (_rowSpacing);
      // Larger covers keep the next row visible as a scrolling cue. Focus
      // restoration uses this same extent rather than an assumed row height.
      return available / (TvVisuals.fixedSurfaces ? 1.65 : 2);
    }
    return MediaQuery.sizeOf(context).width / crossCount / 0.65 +
        MediaQuery.textScalerOf(context).scale(32.0);
  }

  Future<void> _scrollToChannel(
    int channelNumber, {
    bool revealOnly = false,
  }) async {
    if (!scrollController.hasClients) return;
    final crossCount = _gridCrossCount();
    final row = (channelNumber - 1) ~/ crossCount;
    final extent = _gridItemExtent(crossCount);
    final rowOffset = row * (extent + _rowSpacing);
    final position = scrollController.position;
    var target = row == 0 ? 0.0 : _introExtent + rowOffset;
    // Native home expands the spotlight while its first row is visible. Return
    // all the way to that row instead of leaving its introduction scrolled off.
    if (revealOnly && TvMode.enabled && row > 0) {
      final header = _pinnedExtent + MediaQuery.paddingOf(context).top;
      final top = header +
          (_introExtent - _recentExtent) +
          _loadingIndicatorHeight +
          _gridPadding +
          rowOffset;
      final start = top - header - _gridPadding;
      final end = top + extent + _gridPadding - position.viewportDimension;
      // Keep an already visible row stationary. For oversized cards prefer
      // their top below the pinned categories rather than oscillating edges.
      target =
          end > start ? start : position.pixels.clamp(end, start).toDouble();
    }
    target = target.clamp(0.0, position.maxScrollExtent);
    if (TvInputLifecycle.active)
      _traceGrid('scroll_begin', {
        'targetChannel': channelNumber,
        'row': row,
        'targetOffset': target,
        'currentOffset': position.pixels,
        'maxScrollExtent': position.maxScrollExtent,
        'revealOnly': revealOnly
      });
    if ((target - position.pixels).abs() > 0.5) {
      await scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (TvInputLifecycle.active)
      _traceGrid('scroll_end', {
        'targetChannel': channelNumber,
        'offset': scrollController.hasClients ? scrollController.offset : null
      });
  }

  Future<void> _scrollToListEnd() async {
    if (!scrollController.hasClients) return;
    await scrollController.animateTo(
      scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  bool showWindowButton() {
    return GStorage.getSetting(SettingsKeys.showWindowButton);
  }

  Future<void> _selectTag(String tag) async {
    _homeReturnEpoch++;
    _cancelGridFocusRequest();
    _tagSelectionTimer?.cancel();
    ++_summaryRevision;
    _summaryTimer?.cancel();
    if (tag == popularController.currentTag) return;
    tvChannelInputController.cancel();
    if (scrollController.hasClients) {
      unawaited(
        scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
      );
    }
    popularController.setCurrentTag(tag);
    if (tag.isEmpty) {
      popularController.clearBangumiList();
      if (popularController.trendList.isEmpty) {
        await popularController.queryBangumiByTrend();
      }
      return;
    }
    await popularController.queryBangumiByTag(type: 'init');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            controller: scrollController,
            slivers: [
              buildSliverAppBar(),
              if (TvMode.enabled)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: _buildTvSpotlight(),
                  ),
                ),
              if (TvMode.enabled && _recentExtent > 0)
                SliverPersistentHeader(
                    pinned: true,
                    delegate: _RecentWatchHeader(
                      _recentExtent,
                      onOpen: _openRecent,
                      onNavigation: _onRecentNavigation,
                    )),
              SliverToBoxAdapter(
                child: Observer(
                  builder: (_) => AnimatedOpacity(
                    opacity: popularController.isLoadingMore ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: popularController.isLoadingMore
                        ? const LinearProgressIndicator(
                            minHeight: _loadingIndicatorHeight,
                          )
                        : const SizedBox(height: _loadingIndicatorHeight),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  TvMode.enabled ? 24 : StyleString.cardSpace,
                  0,
                  TvMode.enabled ? 24 : StyleString.cardSpace,
                  0,
                ),
                sliver: Observer(
                  builder: (_) {
                    if (popularController.isTimeOut) {
                      return SliverToBoxAdapter(
                        child: SizedBox(
                          height: 400,
                          child: BangumiMirrorErrorWidget(
                            onRetry: () {
                              if (popularController.currentTag.isEmpty) {
                                popularController.queryBangumiByTrend(
                                    type: 'retry');
                              } else {
                                popularController.queryBangumiByTag(
                                    type: 'retry');
                              }
                            },
                            onSettingsReturned: () {
                              if (mounted) {
                                setState(() {});
                              }
                            },
                          ),
                        ),
                      );
                    }
                    return contentGrid(
                      (popularController.currentTag == '')
                          ? popularController.trendList
                          : popularController.bangumiList,
                    );
                  },
                ),
              ),
              if (TvMode.enabled)
                SliverToBoxAdapter(child: Observer(builder: (_) {
                  if (popularController.isLoadingMore ||
                      popularController.canLoadMore ||
                      _visibleBangumiList.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Center(
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: popularController.canRetryLoad
                              ? TvFocusableSurface(
                                  focusNode: _retryFocusNode,
                                  ensureVisibleOnFocus: false,
                                  onKeyEvent: _handleRetryKey,
                                  onPressed: () =>
                                      unawaited(_returnFromRetry(retry: true)),
                                  child: TextButton.icon(
                                    onPressed: () => unawaited(
                                        _returnFromRetry(retry: true)),
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('重试加载更多'),
                                  ),
                                )
                              : const Text('已到列表末尾',
                                  style: TvVisuals.caption)));
                })),
            ],
          ),
          if (TvMode.enabled && _channelInput.isNotEmpty)
            _buildChannelInputOverlay(),
        ],
      ),
      floatingActionButton: TvMode.enabled
          ? null
          : FloatingActionButton(
              onPressed: () => scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut,
              ),
              child: const Icon(Icons.arrow_upward),
            ),
    );
  }

  Widget _buildTvSpotlight() => SizedBox(
        key: const Key('tv-home-spotlight'),
        height: MediaQuery.textScalerOf(context).scale(74),
        child: Observer(
          builder: (_) {
            final items = _visibleBangumiList;
            return ValueListenableBuilder<BangumiItem?>(
              valueListenable: _spotlight,
              builder: (context, selected, _) {
                final item =
                    selected != null && items.any((v) => v.id == selected.id)
                        ? selected
                        : (items.isEmpty ? null : items.first);
                final summary = (item?.summary.isNotEmpty == true
                        ? item!.summary
                        : _summaryCache[item?.id] ?? '')
                    .replaceAll(RegExp(r'<[^>]*>'), '')
                    .replaceAll(RegExp(r'\s+'), ' ');
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item == null
                          ? ''
                          : (item.nameCn.isEmpty ? item.name : item.nameCn),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TvVisuals.heading,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TvVisuals.body.copyWith(color: TvVisuals.muted),
                    ),
                  ],
                );
              },
            );
          },
        ),
      );

  Widget contentGrid(List<BangumiItem> bangumiList) {
    _scheduleDefaultSpotlight(bangumiList);
    final crossCount = _gridCrossCount();
    return SliverPadding(
      padding: const EdgeInsets.all(_gridPadding),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          // 行间距
          mainAxisSpacing: _rowSpacing,
          // 列间距
          crossAxisSpacing: TvMode.enabled
              ? (TvVisuals.fixedSurfaces ? 8 : 12)
              : StyleString.cardSpace,
          // 列数
          crossAxisCount: crossCount,
          mainAxisExtent: _gridItemExtent(crossCount),
        ),
        delegate: SliverChildBuilderDelegate(
          (BuildContext context, int index) {
            final channelNumber = index + 1;
            if (bangumiList.isEmpty) return null;
            final focusNode =
                TvMode.enabled ? _focusNodeForChannel(channelNumber) : null;
            final card = BangumiCardV(
              key: ValueKey(bangumiList[index].id),
              bangumiItem: bangumiList[index],
              channelNumber: TvMode.enabled ? channelNumber : null,
              posterOverlay: TvMode.enabled,
              highlighted: _channelCandidate == channelNumber,
              focusNode: focusNode,
              onKeyEvent: (_, event) => _handleGridKey(
                index,
                bangumiList.length,
                crossCount,
                event,
              ),
              ensureVisibleOnFocus: !TvMode.enabled,
              onFocusChange: TvMode.enabled
                  ? (focused) => _onChannelFocusChanged(channelNumber, focused)
                  : null,
              onPressed: TvMode.enabled
                  ? () => _openChannel(bangumiList[index])
                  : null,
            );
            return focusNode == null
                ? card
                : _GridFocusKeeper(
                    key: ValueKey(bangumiList[index].id),
                    focusNode: focusNode,
                    child: card,
                  );
          },
          childCount: bangumiList.isNotEmpty ? bangumiList.length : 10,
          findChildIndexCallback: (key) {
            if (key is! ValueKey<int>) return null;
            final index = bangumiList.indexWhere(
              (item) => item.id == key.value,
            );
            return index < 0 ? null : index;
          },
        ),
      ),
    );
  }

  Widget _buildChannelInputOverlay() {
    final theme = Theme.of(context);
    final itemCount = _visibleBangumiList.length;
    final channelNumber = int.tryParse(_channelInput) ?? 0;
    final found = channelNumber >= 1 && channelNumber <= itemCount;
    final colorScheme = theme.colorScheme;
    return Positioned(
      top: 18,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: AnimatedContainer(
            key: const Key('tv-channel-input-overlay'),
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            decoration: BoxDecoration(
              color: (found || _channelSearching) &&
                      !_channelLookupFailed &&
                      !_channelLookupLimited
                  ? colorScheme.inverseSurface.withValues(alpha: 0.94)
                  : colorScheme.errorContainer.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 16),
              ],
            ),
            child: Text(
              _channelLookupFailed
                  ? '无法加载 $_channelInput 号节目'
                  : _channelLookupLimited
                      ? '暂未加载到 $_channelInput 号'
                      : _channelSearching
                          ? '正在查找 $_channelInput 号…'
                          : found
                              ? '转到 $_channelInput 号…'
                              : '没有 $_channelInput 号节目',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: (found || _channelSearching) &&
                        !_channelLookupFailed &&
                        !_channelLookupLimited
                    ? colorScheme.onInverseSurface
                    : colorScheme.onErrorContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _scheduleHomeReady(TvDesktopNavigation? navigation) {
    final onReady = navigation?.onHomeReady;
    if (onReady == null || _homeReadyReported || _homeReadyFrameScheduled)
      return;
    _homeReadyFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _homeReadyFrameScheduled = false;
      if (mounted) {
        TvDesktopNavigation.traceStartupFocus(
          'popular-ready',
          focus: FocusManager.instance.primaryFocus,
          current: ModalRoute.of(context)?.isCurrent,
          covered: RouteVisibility.isCoveredOf(context),
          attached: _attached(_focusNodeForTag('')),
          canFocus: _focusNodeForTag('').canRequestFocus,
          epoch: _homeReturnEpoch,
        );
      }
      if (!mounted ||
          !TvMode.enabled ||
          ModalRoute.of(context)?.isCurrent != true ||
          RouteVisibility.isCoveredOf(context) ||
          !_attached(_focusNodeForTag(''))) return;
      _homeReadyReported = true;
      onReady(_focusNodeForTag(''));
    });
  }

  Widget buildSliverAppBar() {
    final theme = Theme.of(context);
    if (TvMode.enabled) {
      final navigation = TvDesktopNavigation.maybeOf(context);
      final categories = Observer(
        builder: (_) {
          _scheduleHomeReady(navigation);
          return SizedBox(
            height: 48,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
              child: Row(
                children: [
                  _buildTvCategoryTab('', 0),
                  for (var i = 0; i < defaultAnimeTags.length; i++)
                    _buildTvCategoryTab(defaultAnimeTags[i], i + 1),
                ],
              ),
            ),
          );
        },
      );
      return SliverAppBar(
        pinned: true,
        toolbarHeight: _tvToolbarHeight,
        elevation: 0,
        titleSpacing: 32,
        backgroundColor: WidgetStateColor.resolveWith((states) =>
            states.contains(WidgetState.scrolledUnder)
                ? TvVisuals.background
                : Colors.transparent),
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: buildActions(),
        title: navigation == null
            ? categories
            : Row(
                children: [
                  Expanded(flex: 40, child: navigation.functionBar(context)),
                  const SizedBox(width: 8),
                  const SizedBox(height: 28, child: VerticalDivider(width: 1)),
                  const SizedBox(width: 8),
                  Expanded(flex: 62, child: categories),
                ],
              ),
      );
    }
    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: 120,
      elevation: 0,
      titleSpacing: 0,
      centerTitle: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      actions: buildActions(),
      title: null,
      flexibleSpace: SafeArea(
        child: dtb.DragToMoveArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double maxExtent = 120 - MediaQuery.of(context).padding.top;
              final t = (1 -
                  ((constraints.maxHeight - kToolbarHeight) /
                          (maxExtent - kToolbarHeight))
                      .clamp(0.0, 1.0));
              // 字重收缩后为 w500，展开时为 w700
              final fontWeight = t < 0.5 ? FontWeight.w700 : FontWeight.w500;
              final fontSize = lerpDouble(28, 20, t)!;
              return Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    top: 8,
                    bottom: 8,
                    right: 60,
                  ),
                  child: SizedBox(
                    height: 44,
                    child: Observer(
                      builder: (_) {
                        final bool isTrend = popularController.currentTag == '';
                        return InkWell(
                          key: selectorKey,
                          borderRadius: BorderRadius.circular(8),
                          onTap: showTagMenu,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isTrend ? '热门番组' : popularController.currentTag,
                                style: theme.textTheme.headlineMedium!.copyWith(
                                  fontWeight: fontWeight,
                                  fontSize: fontSize,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.keyboard_arrow_down,
                                size: fontSize,
                                color: theme.iconTheme.color,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTvCategoryTab(String tag, int index) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selected = popularController.currentTag == tag;
    final label = tag.isEmpty ? '热门' : tag;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: TvFocusableSurface(
        focusNode: _focusNodeForTag(tag),
        ensureVisibleOnFocus: false,
        borderRadius: 12,
        focusScale: 1,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          _homeReturnEpoch++;
          final tags = ['', ...defaultAnimeTags];
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            if (index == 0) {
              Actions.maybeInvoke(context, const TvFocusRailIntent());
            } else {
              _focusNodeForTag(tags[index - 1]).requestFocus();
            }
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            if (index + 1 < tags.length)
              _focusNodeForTag(tags[index + 1]).requestFocus();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _tagSelectionTimer?.cancel();
            final recent = node.enclosingScope?.traversalDescendants.where(
                (n) =>
                    n.context != null &&
                    TvDesktopNavigation.homeFocusOf(n)?.kind ==
                        TvHomeFocusKind.recent);
            if (recent?.isNotEmpty == true) {
              recent!.first.requestFocus();
              return KeyEventResult.handled;
            }
            unawaited(() async {
              if (!mounted || !node.hasFocus || _visibleBangumiList.isEmpty) {
                return;
              }
              await _scrollToChannel(1);
              if (mounted && node.hasFocus && _visibleBangumiList.isNotEmpty) {
                _focusNodeForChannel(1).requestFocus();
              }
            }());
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _tagSelectionTimer?.cancel();
            Actions.maybeInvoke(context, const TvFocusRailIntent());
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        onFocusChange: (focused) {
          if (!focused) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final node = _focusNodeForTag(tag);
            if (!mounted || !node.hasFocus || node.context == null) return;
            final scrollable = Scrollable.maybeOf(node.context!);
            final target = node.context!.findRenderObject();
            if (scrollable == null || target == null) return;
            // Only reveal the horizontal strip. Walking every ancestor also
            // moves the catalog viewport when focus arrives from a lower row.
            scrollable.position.ensureVisible(
              target,
              alignment: 0.5,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
            );
          });
        },
        onPressed: () => unawaited(_selectTag(tag)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? colorScheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: 15,
              color: selected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> buildActions() {
    final actions = <Widget>[
      if (MediaQuery.of(context).orientation == Orientation.portrait)
        IconButton(
          tooltip: '搜索',
          onPressed: () => context.pushNamed('/search/'),
          icon: const Icon(Icons.search),
        ),
    ];
    if (!TvMode.enabled) {
      actions.add(
        IconButton(
          tooltip: '历史记录',
          onPressed: () => context.pushNamed('/settings/history/'),
          icon: const Icon(Icons.history),
        ),
      );
    }
    if (isDesktop()) {
      if (!showWindowButton()) {
        actions.add(
          IconButton(
            tooltip: '退出',
            onPressed: () => windowManager.close(),
            icon: const Icon(Icons.close),
          ),
        );
      }
    }
    return actions;
  }

  Future<void> showTagMenu() async {
    // Calculate the position of the button manually to position the dropdown menu.
    // Using CustomDropdownMenu instead of PopupMenuButton to avoid flickering issues
    // and to support different font sizes in the button and menu items.
    final RenderBox renderBox =
        selectorKey.currentContext!.findRenderObject() as RenderBox;
    final Offset offset = renderBox.localToGlobal(Offset.zero);
    final Size size = renderBox.size;

    final selected = await Navigator.push<String>(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        pageBuilder: (context, animation, secondaryAnimation) {
          return CustomDropdownMenu(
            offset: offset,
            buttonSize: size,
            animation: animation,
            maxWidth: 80,
            items: ['', ...defaultAnimeTags],
            itemBuilder: (item) => item.isEmpty ? '热门番组' : item,
          );
        },
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 150),
      ),
    );

    if (selected == null) return;
    await _selectTag(selected);
  }
}

/// Keep the one focused card attached until a scrolling request transfers
/// focus. Otherwise long-held keys stop reaching the card when its old row is
/// recycled before the new row has finished scrolling into view.
class _GridFocusKeeper extends StatefulWidget {
  const _GridFocusKeeper({
    super.key,
    required this.focusNode,
    required this.child,
  });
  final FocusNode focusNode;
  final Widget child;

  @override
  State<_GridFocusKeeper> createState() => _GridFocusKeeperState();
}

class _GridFocusKeeperState extends State<_GridFocusKeeper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.focusNode.hasFocus;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(updateKeepAlive);
  }

  @override
  void didUpdateWidget(covariant _GridFocusKeeper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(updateKeepAlive);
      widget.focusNode.addListener(updateKeepAlive);
      updateKeepAlive();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(updateKeepAlive);
    super.dispose();
  }
}

class _RecentWatchHeader extends SliverPersistentHeaderDelegate {
  _RecentWatchHeader(this.height,
      {required this.onOpen, required this.onNavigation});
  final double height;
  final Future<void> Function(History, FocusNode) onOpen;
  final VoidCallback onNavigation;
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      ColoredBox(
          color: TvVisuals.background.withValues(alpha: .9),
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child:
                  TvRecentWatch(onOpen: onOpen, onNavigation: onNavigation)));
  @override
  bool shouldRebuild(_RecentWatchHeader oldDelegate) =>
      oldDelegate.height != height ||
      oldDelegate.onOpen != onOpen ||
      oldDelegate.onNavigation != onNavigation;
}
