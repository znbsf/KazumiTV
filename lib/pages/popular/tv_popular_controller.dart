import 'dart:math';

import 'package:kazumi/pages/popular/popular_controller.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:mobx/mobx.dart';

/// TV category state; mobile and desktop keep the upstream controller.
class TvPopularController extends PopularController {
  static const _pageSize = 24;
  static const _sampleSize = 100;
  static const _maxDirectoryItems = 1008;
  static const _maxPagedBatches = _maxDirectoryItems ~/ _pageSize;
  static const _maxSampleBatches =
      (_maxDirectoryItems + _sampleSize - 1) ~/ _sampleSize;

  int _tagQueryGeneration = 0;
  // Small session cache of metadata only; images keep their own cache.
  final _tagCache = <(bool, String), _TvDirectoryState>{};
  final _trendCache = <bool, _TvDirectoryState>{};
  (bool, String)? _activeTagKey;
  _TvDirectoryState? _activeTagState;
  static const _tagCacheLifetime = Duration(minutes: 10);
  static const _maxCachedTags = 8;

  bool get _bangumiMirrorEnabled =>
      GStorage.getSetting(SettingsKeys.enableBangumiProxy);

  _TvDirectoryState? get _currentState {
    final mirror = _bangumiMirrorEnabled;
    if (currentTag.isEmpty) return _trendCache[mirror];
    return _activeTagKey == (mirror, currentTag) ? _activeTagState : null;
  }

  @override
  bool get canLoadMore => !isLoadingMore && (_currentState?.hasMore ?? true);

  @override
  bool get canRetryLoad {
    final state = _currentState;
    final maxBatches = currentTag.isEmpty || _bangumiMirrorEnabled
        ? _maxPagedBatches
        : _maxSampleBatches;
    return !isLoadingMore &&
        state != null &&
        state.retryable &&
        state.items.length < _maxDirectoryItems &&
        state.batches < maxBatches;
  }

  void _publishLoading() {
    final state = _currentState;
    isLoadingMore = state?.request != null;
    // An empty API response can also mean a swallowed network failure. Keep
    // already loaded cards visible, stop automatic requests, and let an explicit
    // retry fetch the same cursor without clearing them.
    isTimeOut = state != null &&
        state.request == null &&
        state.items.isEmpty &&
        !state.hasMore;
  }

  @override
  void setCurrentTag(String s) {
    if (s == currentTag) return;
    runInAction(() {
      _tagQueryGeneration += 1;
      _activeTagState?.request = null;
      currentTag = s;
      final trend = s.isEmpty ? _trendCache[_bangumiMirrorEnabled] : null;
      if (trend != null) trendList = ObservableList.of(trend.items);
      _publishLoading();
    });
  }

  @override
  Future<void> queryBangumiByTrend({String type = 'add'}) =>
      AsyncAction('TvPopularController.queryBangumiByTrend').run(() async {
        final mirror = _bangumiMirrorEnabled;
        final state = type == 'init'
            ? (_trendCache[mirror] = _TvDirectoryState())
            : _trendCache.putIfAbsent(mirror, _TvDirectoryState.new);
        trendList = ObservableList.of(state.items);
        if (type == 'retry') state.retry(_maxPagedBatches);
        if (state.request != null || !state.hasMore) {
          _publishLoading();
          return;
        }
        final request = Object();
        state.request = request;
        _publishLoading();
        try {
          final result = mirror
              ? await BangumiApi.getBangumiMirrorPopularSubjects(
                  limit: _pageSize,
                  offset: state.offset,
                )
              : await BangumiApi.getBangumiTrendsList(
                  limit: _pageSize,
                  offset: state.offset,
                );
          if (_trendCache[mirror] != state || state.request != request) return;
          state.append(
            result,
            pageSize: _pageSize,
            maxBatches: _maxPagedBatches,
            stopOnShortBatch: true,
          );
          // Trends retain their own cache while a category is visible. Only the
          // currently selected provider may replace the public trends list.
          if (mirror == _bangumiMirrorEnabled) {
            trendList = ObservableList.of(state.items);
          }
        } catch (_) {
          if (_trendCache[mirror] == state && state.request == request) {
            state.stop(_TvDirectoryStopReason.error);
          }
        } finally {
          if (state.request == request) state.request = null;
          _publishLoading();
        }
      });

  @override
  Future<void> queryBangumiByTag({String type = 'add'}) {
    if (currentTag.isEmpty) return queryBangumiByTrend(type: type);
    return AsyncAction('TvPopularController.queryBangumiByTag').run(() async {
      final mirror = _bangumiMirrorEnabled;
      final tag = currentTag;
      final cacheKey = (mirror, tag);
      if (type == 'init' || _activeTagKey != cacheKey) {
        _tagQueryGeneration += 1;
        _activeTagState?.request = null;
        final cached = _tagCache.remove(cacheKey);
        if (cached != null &&
            DateTime.now().difference(cached.updatedAt) < _tagCacheLifetime) {
          _tagCache[cacheKey] = cached;
          _activeTagState = cached;
        } else {
          _activeTagState = _TvDirectoryState();
        }
        _activeTagKey = cacheKey;
        bangumiList = ObservableList.of(_activeTagState!.items);
        if (cached == _activeTagState && type == 'init') {
          _publishLoading();
          return;
        }
      }
      final state = _activeTagState!;
      final maxBatches = mirror ? _maxPagedBatches : _maxSampleBatches;
      if (type == 'retry') state.retry(maxBatches);
      if (state.request != null || !state.hasMore) {
        _publishLoading();
        return;
      }
      final requestGeneration = _tagQueryGeneration;
      final request = Object();
      state.request = request;
      _publishLoading();
      bool ownsRequest() =>
          requestGeneration == _tagQueryGeneration &&
          tag == currentTag &&
          mirror == _bangumiMirrorEnabled &&
          _activeTagState == state &&
          state.request == request;
      try {
        final result = mirror
            ? await BangumiApi.getBangumiMirrorPopularSubjects(
                tag: tag,
                limit: _pageSize,
                offset: state.offset,
              )
            : await BangumiApi.getBangumiList(
                rank: Random().nextInt(8000) + 1,
                tag: tag,
              );
        if (!ownsRequest()) return;
        state.append(
          result,
          pageSize: mirror ? _pageSize : _sampleSize,
          maxBatches: maxBatches,
          stopOnShortBatch: mirror,
        );
        bangumiList = ObservableList.of(state.items);
        if (state.items.isNotEmpty) {
          _tagCache.remove(cacheKey);
          _tagCache[cacheKey] = state;
          while (_tagCache.length > _maxCachedTags) {
            _tagCache.remove(_tagCache.keys.first);
          }
        }
      } catch (_) {
        if (ownsRequest()) state.stop(_TvDirectoryStopReason.error);
      } finally {
        if (state.request == request) state.request = null;
        _publishLoading();
      }
    });
  }
}

enum _TvDirectoryStopReason {
  emptyResponse,
  error,
  shortBatch,
  noProgress,
  limit
}

class _TvDirectoryState {
  final items = <BangumiItem>[];
  DateTime updatedAt = DateTime.now();
  int offset = 0;
  int batches = 0;
  bool hasMore = true;
  _TvDirectoryStopReason? stopReason;
  Object? request;

  bool get retryable =>
      stopReason == _TvDirectoryStopReason.emptyResponse ||
      stopReason == _TvDirectoryStopReason.error;

  void stop(_TvDirectoryStopReason reason) {
    stopReason = reason;
    hasMore = false;
  }

  void retry(int maxBatches) {
    if (retryable &&
        items.length < TvPopularController._maxDirectoryItems &&
        batches < maxBatches) {
      stopReason = null;
      hasMore = true;
    }
  }

  void append(
    List<BangumiItem> result, {
    required int pageSize,
    required int maxBatches,
    required bool stopOnShortBatch,
  }) {
    final ids = items.map((item) => item.id).toSet();
    final previousCount = items.length;
    for (final item in result) {
      if (items.length >= TvPopularController._maxDirectoryItems) break;
      if (ids.add(item.id)) items.add(item);
    }
    if (result.isNotEmpty) {
      offset += pageSize;
      batches += 1;
    }
    updatedAt = DateTime.now();
    if (result.isEmpty) {
      stop(_TvDirectoryStopReason.emptyResponse);
    } else if (items.length >= TvPopularController._maxDirectoryItems ||
        batches >= maxBatches) {
      stop(_TvDirectoryStopReason.limit);
    } else if (items.length == previousCount) {
      stop(_TvDirectoryStopReason.noProgress);
    } else if (stopOnShortBatch && result.length < pageSize) {
      stop(_TvDirectoryStopReason.shortBatch);
    } else {
      stopReason = null;
      hasMore = true;
    }
  }
}
