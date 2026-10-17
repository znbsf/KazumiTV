import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/pages/info/info_page.dart';
import 'package:kazumi/pages/info/source_sheet.dart';
import 'package:kazumi/pages/info/source_health_page.dart';
import 'package:kazumi/pages/info/tv_detail_actions.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/source_health/source_health.dart';
import 'package:kazumi/services/source_health/source_health_preferences.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'source_health_test.dart' show FakeRule;

class _SearchRule extends FakeRule {
  _SearchRule(super.label);
  int roadCalls = 0;
  @override
  Future<List<Road>> queryChapterRoads(String source,
      {RuleCancelToken? cancelToken}) {
    roadCalls++;
    return super.queryChapterRoads(source, cancelToken: cancelToken);
  }
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('recorded_entry_');
    PathProviderPlatform.instance = _Paths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  for (final mode in ['none', 'disabled', 'saved', 'failed', 'preferenceOnly']) {
    testWidgets(
        'start watching $mode retains ordinary search without health probes',
        (tester) async {
      TvMode.setEnabledForTesting(true);
      addTearDown(() => TvMode.setEnabledForTesting(false));
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final saved = _SearchRule('Saved');
      final untested = _SearchRule('Untested');
      if (mode == 'failed') {
        saved.search =
            () async => PluginSearchResponse(pluginName: saved.name, data: []);
      }
      final plugins = PluginsController()..pluginList.addAll([saved, untested]);
      final collect = _Collect();
      final info = InfoController(collect);
      final subject = BangumiItem(
          id: 71,
          type: 2,
          name: 'Target',
          nameCn: '',
          summary: 'Fixture',
          airDate: '',
          airWeekday: 1,
          rank: 0,
          images: {},
          tags: [],
          alias: [],
          ratingScore: 8,
          votes: 10,
          votesCount: List.filled(10, 1),
          info: '');
      await tester.runAsync(() async {
        await GStorage.putSetting(SettingsKeys.firstSourceAutoSelect, mode != 'disabled');
        await GStorage.putSetting(SettingsKeys.sourceHealthGlobal, true);
        await GStorage.putSetting(SettingsKeys.sourceHealthPreferences, '{}');
        await GStorage.putSetting(
            SettingsKeys.sourceHealthRecords,
            HealthRecordCodec.encode(mode == 'saved' || mode == 'failed'
                ? [
                    HealthRecord(
                        subject: 99,
                        rule: saved.name,
                        fingerprint: ruleFingerprint(saved),
                        environment: 'other',
                        checkedAt: DateTime.now(),
                        stage: HealthStage.firstFrame,
                        reason: 'confirmed')
                  ]
                : []));
        if (mode == 'preferenceOnly') {
          await SourceHealthPreferences.remember(71, saved);
        }
      });
      OnlineVideoPlaybackArgs? opened;
      await tester.pumpWidget(ModularApp(
          module: createModule(register: (c) {
            c.addInstance<CollectController>(collect);
            c.addInstance<PluginsController>(plugins);
            c.addInstance<IHistoryRepository>(_History());
            c.route('/',
                child: (_, __) =>
                    InfoPage(inputBangumiItem: subject, infoController: info));
            c.route('/video/', child: (_, state) {
              opened = state.arguments as OnlineVideoPlaybackArgs;
              return const Scaffold(body: Text('Normal video route'));
            });
          }),
          child: Builder(
              builder: (context) => MaterialApp.router(
                  routerConfig: ModularApp.routerConfigOf(context)))));
      await tester.pumpAndSettle();
      final action =
          tester.widget<TvDetailActions>(find.byType(TvDetailActions));
      action.playFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(SourceHealthPage), findsNothing);
      if (mode == 'saved') {
        expect(opened?.plugin, same(saved));
        expect(opened?.roads, isNotEmpty);
        expect(saved.calls, 1);
        expect(untested.calls, 0);
        expect(find.byType(SourceSheet), findsNothing);
      } else {
        expect(opened, isNull);
        expect(find.byType(SourceSheet), findsOneWidget);
        expect(tester.widget<SourceSheet>(find.byType(SourceSheet)).autoSearchOnOpen,
            isTrue);
        expect(saved.calls, mode == 'failed' ? 2 : 1);
        expect(untested.calls, 1);
        expect(info.pluginSearchStatus[untested.name], PluginSearchStatus.success);
        expect(info.pluginSearchResponseList.any((r) => r.pluginName == untested.name),
            isTrue);
        // Ordinary title search must not resolve or play every source.
        expect(untested.roadCalls, 0);
        expect(saved.roadCalls, 0);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
