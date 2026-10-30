import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/plugin/plugin_search_service.dart';
import 'source_health_test.dart' show FakeRule;
import 'package:kazumi/services/plugin/rule_engine_models.dart';

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

class _ControlledRule extends FakeRule {
  _ControlledRule(super.label);
  final tokens = <RuleCancelToken>[];
  final pending = <Completer<PluginSearchResponse>>[];
  @override
  Future<PluginSearchResponse> queryBangumi(String keyword,
      {bool shouldRethrow = false, RuleCancelToken? cancelToken}) {
    tokens.add(cancelToken!);
    final result = Completer<PluginSearchResponse>();
    pending.add(result);
    return result.future;
  }
}

PluginSearchResponse _result(String source, String title) =>
    PluginSearchResponse(
      pluginName: source,
      data: [SearchItem(name: title, src: '/$title')],
    );

void main() {
  test('bounded search publishes first result without waiting for slow sources',
      () async {
    final rules = List.generate(7, (i) => _ControlledRule('source$i'));
    final info = InfoController(_Collect());
    final service = PluginSearchService(
        infoController: info,
        pluginsController: PluginsController()..pluginList.addAll(rules),
        maxConcurrent: 2);
    final all = service.queryAllSource('title');
    expect(rules.where((r) => r.pending.isNotEmpty).length, 2);
    rules[1].pending.single.complete(_result(rules[1].name, 'first'));
    await Future<void>.delayed(Duration.zero);
    expect(info.pluginSearchResponseList.single.data.single.name, 'first');
    expect(rules[2].pending.length, 1);
    service.cancel();
    for (final r in rules.take(3)) {
      if (!r.pending.single.isCompleted)
        expect(r.tokens.single.isCancelled, isTrue);
      if (!r.pending.single.isCompleted)
        r.pending.single.complete(_result(r.name, 'late'));
    }
    await all;
    expect(rules.skip(3).every((r) => r.pending.isEmpty), isTrue);
    expect(info.pluginSearchResponseList.single.data.single.name, 'first');
  });

  test('replacement cancels only its own source and ignores late failure',
      () async {
    final a = _ControlledRule('a');
    final b = _ControlledRule('b');
    final info = InfoController(_Collect());
    final service = PluginSearchService(
        infoController: info,
        pluginsController: PluginsController()..pluginList.addAll([a, b]));
    final old = service.queryAllSource('old');
    final newer = service.querySource('new', 'a');
    expect(a.tokens.first.isCancelled, isTrue);
    expect(b.tokens.single.isCancelled, isFalse);
    a.pending.last.complete(_result('a', 'new'));
    await newer;
    a.pending.first.completeError(StateError('late'));
    b.pending.single.complete(_result('b', 'other'));
    await old;
    expect(info.pluginSearchResponseList.map((r) => r.data.single.name),
        ['new', 'other']);
  });
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
