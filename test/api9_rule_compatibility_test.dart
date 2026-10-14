import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/plugin/api_rule_strategy.dart';
import 'package:kazumi/services/plugin/plugin_import_parser.dart';
import 'package:kazumi/services/plugin/rule_engine.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/utils/encoding.dart';
import 'package:dio/dio.dart';

Map<String, dynamic> _rule({String api = '9', String? template}) => {
      'api': api,
      'name': 'API compatibility fixture',
      'baseURL': 'https://example.invalid',
      'searchMode': 'api',
      'chapterMode': 'xpath',
      'searchApiConfig': {
        'request': {'url': 'https://example.invalid/search'},
        'listPath': r'$.data[*]',
        'namePath': r'$.name',
        'sourcePath': r'$.id',
        if (template != null) 'sourceTemplate': template,
      },
      'chapterRoads': '//ul',
      'chapterResult': '//a',
    };

void main() {
  const strategy = ApiRuleStrategy();
  test('API 8 raw sources keep their existing meaning and serialization', () {
    final plugin = Plugin.fromJson(_rule(api: '8'));
    final config = plugin.searchApiConfig;
    expect(config.sourceTemplate, isEmpty);
    expect(config.toJson().containsKey('sourceTemplate'), isFalse);
    for (final source in ['123', '/show/1', 'https://example.invalid/show/1']) {
      final result = strategy.parseSearch(
          jsonEncode({
            'data': [
              {'name': 'Example', 'id': source}
            ]
          }),
          config);
      expect(result.items.single.src, source);
    }
    expect(plugin.requiresNewerClient, isFalse);
  });

  test('API 9 templates encode IDs and replace adjacent and repeated tokens',
      () {
    final config = Plugin.fromJson(
            _rule(template: ' https://example.invalid/GV@source/?id=@source '))
        .searchApiConfig;
    for (final id in <Object>[123, 'a/b ?#中文']) {
      final encoded = Uri.encodeComponent(id.toString());
      final result = strategy.parseSearch(
          jsonEncode({
            'data': [
              {'name': 'Example', 'id': id}
            ]
          }),
          config);
      expect(result.items.single.src,
          'https://example.invalid/GV$encoded/?id=$encoded');
    }
    expect(
        () => strategy.validateSearchConfig(
            ApiSearchConfig(sourceTemplate: 'https://example.invalid/fixed')),
        throwsA(isA<ApiRuleFormatException>()));
  });

  test('API 9 survives JSON, share import and temporarily inactive mode', () {
    expect(ApiEndpoints.apiLevel, 9);
    final plugin = Plugin.fromJson(
        _rule(template: 'https://example.invalid/show/@source'));
    final imported = PluginImportParser.parse(
        jsonToKazumiBase64(jsonEncode(plugin.toJson())));
    expect(imported.failures, isEmpty);
    final restored = imported.plugins.single..searchMode = RuleMode.xpath;
    expect(Plugin.fromJson(restored.toJson()).searchApiConfig.sourceTemplate,
        'https://example.invalid/show/@source');
    expect(PluginImportParser.parse(jsonEncode(_rule(api: '10'))).plugins,
        isEmpty);
  });

  test('templated API result feeds XPath detail and normalized episode URLs',
      () async {
    final plugin =
        Plugin.fromJson(_rule(template: 'https://example.invalid/GV@source/'));
    final executor = _Executor();
    final engine = RuleEngine(requestExecutor: executor, logFailures: false);
    final config = RuleExecutionConfig(
      pluginName: plugin.name,
      baseUrl: plugin.baseUrl,
      usePost: false,
      searchMode: RuleMode.api,
      chapterMode: RuleMode.xpath,
      searchUrl: '',
      searchList: '',
      searchName: '',
      searchResult: '',
      searchApiConfig: plugin.searchApiConfig,
      chapterApiConfig: plugin.chapterApiConfig,
      antiCrawlerConfig: plugin.antiCrawlerConfig,
      chapterRoads: plugin.chapterRoads,
      chapterResult: plugin.chapterResult,
    );
    final results = await engine.search(config, 'Example');
    final chapters =
        await engine.queryChapters(config, results.response.data.single.src);
    expect(executor.urls,
        ['https://example.invalid/search', 'https://example.invalid/GV123']);
    expect(chapters.roads.single.data, ['https://example.invalid/play/1']);
    expect(chapters.roads.single.identifier, ['EP1']);
  });
}

class _Executor implements RuleRequestExecutor {
  final urls = <String>[];
  @override
  Future<String> execute(
      PreparedRuleRequest request, RuleExecutionConfig config,
      {CancelToken? cancelToken}) async {
    urls.add(request.url);
    return urls.length == 1
        ? '{"data":[{"name":"Example","id":123}]}'
        : '<ul><li><a href="/play/1">EP1</a></li></ul>';
  }
}
