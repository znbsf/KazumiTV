import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/plugin/plugin_search_service.dart';
import 'source_health_test.dart' show FakeRule;

class _Collect implements CollectController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HarvestRule extends FakeRule {
  _HarvestRule(super.label);
  PluginSearchResponse? harvested;

  @override
  PluginSearchResponse? parseHarvestedSearch(String html) => harvested;
}

PluginSearchResponse _result(String source, String title) =>
    PluginSearchResponse(
      pluginName: source,
      data: [SearchItem(name: title, src: '/$title')],
    );

void main() {
  for (final lateFailure in [false, true]) {
    test('verified results survive late search failure=$lateFailure', () async {
      final pending = Completer<PluginSearchResponse>();
      final rule = _HarvestRule('source')
        ..search = (() => pending.future)
        ..harvested = _result('source', 'verified');
      final other = _HarvestRule('other');
      final info = InfoController(_Collect());
      final plugins = PluginsController()..pluginList.addAll([rule, other]);
      final service =
          PluginSearchService(infoController: info, pluginsController: plugins);
      final old = service.querySource('old', rule.name);
      expect(service.applyHarvestedSearchResult(rule.name, 'fixture'), isTrue);
      if (lateFailure) {
        pending.completeError(StateError('late request failure'));
      } else {
        pending.complete(_result(rule.name, 'old'));
      }
      await old;
      expect(info.pluginSearchStatus[rule.name], PluginSearchStatus.success);
      expect(info.pluginSearchResponseList.single.data.single.name, 'verified');
      // Retiring one request must not close the service or other sources.
      await service.querySource('other', other.name);
      rule.search = () async => _result(rule.name, 'new');
      await service.querySource('new', rule.name);
      expect(info.pluginSearchResponseList.map((r) => r.data.single.name),
          ['Target', 'new']);
      service.cancel();
    });
  }

  test('unparseable harvested page leaves pending search authoritative',
      () async {
    final pending = Completer<PluginSearchResponse>();
    final rule = _HarvestRule('source')..search = () => pending.future;
    final info = InfoController(_Collect());
    final service = PluginSearchService(
        infoController: info,
        pluginsController: PluginsController()..pluginList.add(rule));
    final old = service.querySource('query', rule.name);
    expect(service.applyHarvestedSearchResult(rule.name, 'invalid'), isFalse);
    pending.complete(_result(rule.name, 'network'));
    await old;
    expect(info.pluginSearchResponseList.single.data.single.name, 'network');
    service.cancel();
    expect(service.applyHarvestedSearchResult(rule.name, 'fixture'), isFalse);
  });
}
