// Debug-only local search fixture; no external requests.
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/pages/info/info_page.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/repositories/history_repository.dart';

import 'package:kazumi/plugins/plugins.dart';

class FakeRule extends Plugin {
  FakeRule(String label)
      : super(
          api: '9',
          type: 'anime',
          name: label,
          version: '1',
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
  Future<PluginSearchResponse> Function()? search;
  int calls = 0;
  @override
  Future<PluginSearchResponse> queryBangumi(
    String keyword, {
    bool shouldRethrow = false,
    RuleCancelToken? cancelToken,
  }) async {
    calls++;
    debugPrint('FIRST_SEARCH_QA source=$name calls=$calls');
    return search != null
        ? await search!()
        : PluginSearchResponse(
            pluginName: name,
            data: [SearchItem(name: 'Target', src: '/target')],
          );
  }

  @override
  Future<List<Road>> queryChapterRoads(
    String source, {
    RuleCancelToken? cancelToken,
  }) async {
    debugPrint('FIRST_SEARCH_QA UNEXPECTED_ROAD_RESOLUTION');
    return [
        Road(name: 'main', data: ['/ep1'], identifier: ['1']),
      ];
  }
}

class _Collect implements CollectController {
  @override
  int getCollectType(BangumiItem item) => 0;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _History implements IHistoryRepository {
  @override
  List<History> getAllHistories() => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget buildFirstSearchFixture() {
  final collect = _Collect();
  final info = InfoController(collect);
  final rules = PluginsController()..pluginList.addAll([FakeRule('Local source A'), FakeRule('Local source B')]);
  final subject = BangumiItem(id: 99171, type: 2, name: 'Target', nameCn: '',
    summary: 'Local fixture: Start watching must automatically search titles, with no health probe.',
    airDate: '', airWeekday: 1, rank: 0, images: {}, tags: [], alias: [],
    ratingScore: 8, votes: 10, votesCount: List.filled(10, 1), info: '');
  return ModularApp(module: createModule(register: (c) {
    c.addInstance<CollectController>(collect);
    c.addInstance<PluginsController>(rules);
    c.addInstance<IHistoryRepository>(_History());
    c.route('/', child: (_, __) => InfoPage(inputBangumiItem: subject, infoController: info));
  }), child: Builder(builder: (context) => MaterialApp.router(
    theme: ThemeData.light(useMaterial3: true),
    routerConfig: ModularApp.routerConfigOf(context))));
}
