import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/repositories/collect_crud_repository.dart';
import 'package:kazumi/services/player/history_playback_service.dart';
import 'package:kazumi/services/plugin/plugin_search_service.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;

class _SearchRule extends Plugin {
  _SearchRule(String name, {super.enabled})
      : super(
          api: '1',
          type: 'anime',
          name: name,
          version: '1.0',
          muliSources: true,
          useWebview: true,
          useNativePlayer: true,
          usePost: false,
          useLegacyParser: false,
          adBlocker: false,
          userAgent: '',
          baseUrl: 'https://example.invalid',
          searchURL: '',
          searchList: '',
          searchName: '',
          searchResult: '',
          chapterRoads: '',
          chapterResult: '',
          referer: '',
        );
  int searches = 0;
  int chapters = 0;
  Future<PluginSearchResponse>? response;

  @override
  Future<PluginSearchResponse> queryBangumi(
    String keyword, {
    bool shouldRethrow = false,
    RuleCancelToken? cancelToken,
  }) async {
    searches++;
    if (response != null) return await response!;
    return PluginSearchResponse(pluginName: name, data: [
      SearchItem(name: 'fixture', src: '/fixture'),
    ]);
  }

  @override
  Future<List<Road>> queryChapterRoads(
    String source, {
    RuleCancelToken? cancelToken,
  }) async {
    chapters++;
    return [
      Road(name: 'main', data: ['/episode'], identifier: ['1'])
    ];
  }
}

class _UnusedDownload extends Fake implements DownloadController {}

class _UnusedCollect extends Fake implements ICollectCrudRepository {}

void main() {
  test('a source paused while waiting for a search slot never starts',
      () async {
    final pending = Completer<PluginSearchResponse>();
    final running = _SearchRule('running')..response = pending.future;
    final queued = _SearchRule('queued');
    final controller = PluginsController(pluginJsonWriter: (_) async {})
      ..pluginList.addAll([running, queued]);
    final info = InfoController(CollectController(_UnusedCollect()));
    final service = PluginSearchService(
        infoController: info, pluginsController: controller, maxConcurrent: 1);
    final search = service.queryAllSource('fixture');
    expect(running.searches, 1);
    expect(queued.searches, 0);
    await controller.setPluginEnabled('queued', false);
    pending.complete(PluginSearchResponse(pluginName: 'running', data: []));
    await search;
    expect(queued.searches, 0);
    expect(info.pluginSearchResponseList.map((e) => e.pluginName), ['running']);
    service.cancel();
  });

  test('paused sources are excluded from all and individual searches',
      () async {
    final enabled = _SearchRule('enabled');
    final paused = _SearchRule('paused', enabled: false);
    final controller = PluginsController()
      ..pluginList.addAll([enabled, paused]);
    final info = InfoController(CollectController(_UnusedCollect()));
    final service = PluginSearchService(
        infoController: info, pluginsController: controller);
    await service.queryAllSource('fixture');
    await service.querySource('fixture', 'paused');
    expect(enabled.searches, 1);
    expect(paused.searches, 0);
    expect(info.pluginSearchStatus.keys, ['enabled']);
    expect(info.pluginSearchResponseList.single.pluginName, 'enabled');
    expect(
        service.applyHarvestedSearchResult('paused', '<html></html>'), isFalse);
  });

  test('pausing an in-flight search prevents its late result being published',
      () async {
    final pending = Completer<PluginSearchResponse>();
    final rule = _SearchRule('source')..response = pending.future;
    final controller = PluginsController(pluginJsonWriter: (_) async {})
      ..pluginList.add(rule);
    final info = InfoController(CollectController(_UnusedCollect()));
    final service = PluginSearchService(
        infoController: info, pluginsController: controller);
    final search = service.queryAllSource('fixture');
    await controller.setPluginEnabled('source', false);
    pending.complete(PluginSearchResponse(pluginName: 'source', data: [
      SearchItem(name: 'late', src: '/late'),
    ]));
    await search;
    expect(info.pluginSearchResponseList, isEmpty);
    expect(controller.validityTracker.isSearchValid('source'), isFalse);
  });

  for (final lateFailure in [false, true]) {
    test('pause then resume retires the old search failure=$lateFailure',
        () async {
      final pending = Completer<PluginSearchResponse>();
      final rule = _SearchRule('source')..response = pending.future;
      final controller = PluginsController(pluginJsonWriter: (_) async {})
        ..pluginList.add(rule);
      final info = InfoController(CollectController(_UnusedCollect()));
      final service = PluginSearchService(
          infoController: info, pluginsController: controller);
      final search = service.querySource('old', 'source');
      await controller.setPluginEnabled('source', false);
      await controller.setPluginEnabled('source', true);
      if (lateFailure) {
        pending.completeError(StateError('late failure'));
      } else {
        pending.complete(PluginSearchResponse(pluginName: 'source', data: [
          SearchItem(name: 'old', src: '/old'),
        ]));
      }
      await search;
      expect(info.pluginSearchResponseList, isEmpty);
      expect(info.pluginSearchStatus['source'], PluginSearchStatus.pending);
      expect(controller.validityTracker.isSearchValid('source'), isFalse);
      service.cancel();
    });
  }

  test('history cannot reopen a paused source or request its episode list',
      () async {
    final rule = _SearchRule('paused', enabled: false);
    final controller = PluginsController()..pluginList.add(rule);
    final history = History(
        BangumiItem.fromJson({
          'id': 1,
          'name': 'fixture',
          'rating': <String, dynamic>{},
          'images': <String, String>{},
        }),
        1,
        'paused',
        DateTime.utc(2026),
        'https://example.invalid/detail',
        '1');
    final service = HistoryPlaybackService(controller, _UnusedDownload());
    expect(await service.open(history), isA<HistoryPlaybackUnavailable>());
    expect(rule.chapters, 0);
  });
}
