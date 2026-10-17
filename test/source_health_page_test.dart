import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/info/source_health_page.dart';
import 'package:kazumi/services/source_health/source_health.dart';
import 'package:kazumi/services/source_health/source_health_preferences.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'source_health_test.dart' show FakeRule;

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

BangumiItem _item() => BangumiItem(
      id: 1,
      type: 2,
      name: 'Target',
      nameCn: '',
      summary: '',
      airDate: '',
      airWeekday: 1,
      rank: 0,
      images: {},
      tags: [],
      alias: [],
      ratingScore: 0,
      votes: 0,
      votesCount: [],
      info: '',
    );
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late PathProviderPlatform original;
  setUpAll(() async {
    Logger.level = Level.off;
    temp = await Directory.systemTemp.createTemp('health_widget_');
    original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(temp.path);
    Hive.init(temp.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = original;
    await temp.delete(recursive: true);
  });
  test(
    'manual source preference is per-subject and invalidates on rule edit',
    () async {
      final p = FakeRule('chosen');
      await SourceHealthPreferences.remember(1, p);
      expect(SourceHealthPreferences.preferred(1, [p]), same(p));
      expect(SourceHealthPreferences.preferred(2, [p]), isNull);
      p.version = '2';
      expect(SourceHealthPreferences.preferred(1, [p]), isNull);
    },
  );
  testWidgets('manual health page starts by remote OK without a focus move',
      (tester) async {
    await tester.runAsync(
        () => GStorage.putSetting(SettingsKeys.sourceHealthRecords, ''));
    final rule = FakeRule('empty')
      ..search =
          () async => PluginSearchResponse(pluginName: 'empty', data: []);
    await tester.pumpWidget(MaterialApp(
        home: SourceHealthPage(
      subject: _item(),
      plugins: [rule],
      persistRecord: (_) async {},
    )));
    await tester.pumpAndSettle();
    final start = find.widgetWithText(FilledButton, '开始检测');
    expect(
        Focus.of(tester.element(
                find.descendant(of: start, matching: find.text('开始检测'))))
            .hasFocus,
        isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(rule.calls, 1);
    expect(find.text('empty：搜索无结果'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('health rows hide absent episode and retain recorded episode',
      (tester) async {
    HealthRecord record(String rule, String episode) => HealthRecord(
        subject: 1,
        rule: rule,
        fingerprint: 'fingerprint',
        environment: 'env',
        checkedAt: DateTime.utc(2026, 10, 17),
        stage: episode.isEmpty ? HealthStage.noMatch : HealthStage.firstFrame,
        reason: 'no_search_results',
        episode: episode,
        ruleVersion: '1');
    await tester.runAsync(() => GStorage.putSetting(
        SettingsKeys.sourceHealthRecords,
        HealthRecordCodec.encode([record('empty', ''), record('ready', '1')])));
    await tester.pumpWidget(MaterialApp(
        home: SourceHealthPage(subject: _item(), plugins: const [])));
    await tester.pumpAndSettle();
    final empty = find.ancestor(
        of: find.text('empty：搜索无结果'), matching: find.byType(ListTile));
    final ready = find.ancestor(
        of: find.text('ready：已观察到播放器首帧'), matching: find.byType(ListTile));
    expect((tester.widget<ListTile>(empty).subtitle as Text).data,
        isNot(contains('第')));
    expect((tester.widget<ListTile>(ready).subtitle as Text).data,
        contains('第 1 集'));
    await tester.runAsync(
        () => GStorage.putSetting(SettingsKeys.sourceHealthRecords, ''));
  });
  testWidgets('automatic success returns its matching candidate after cleanup',
      (tester) async {
    await tester.runAsync(
        () => GStorage.putSetting(SettingsKeys.sourceHealthPreferences, ''));
    final navigator = GlobalKey<NavigatorState>();
    HealthCandidate? selected;
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator, home: const Scaffold(body: Text('home'))));
    navigator.currentState!
        .push<HealthCandidate>(MaterialPageRoute(
            builder: (_) => SourceHealthPage(
                subject: _item(),
                plugins: [FakeRule('ready')],
                persistRecord: (_) async {},
                autoSelect: true,
                playbackProbe: (candidate, run) async =>
                    HealthStage.firstFrame)))
        .then((value) => selected = value);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(SourceHealthPage), findsNothing);
    expect(selected?.plugin.name, 'ready');
    expect(selected?.item.name, 'Target');
    expect(tester.takeException(), isNull);
  });
  for (final useBack in [false, true]) {
    testWidgets(
      'cancel ${useBack ? 'Back' : 'button'} exits active run and returns focus',
      (tester) async {
        await tester.runAsync(() =>
            GStorage.putSetting(SettingsKeys.sourceHealthPreferences, ''));
        final navigator = GlobalKey<NavigatorState>();
        final focus = FocusNode();
        addTearDown(focus.dispose);
        var started = false;
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  autofocus: true,
                  focusNode: focus,
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SourceHealthPage(
                          subject: _item(),
                          plugins: [FakeRule('a')],
                          autoSelect: true,
                          playbackProbe: (candidate, run) async {
                            started = true;
                            await run.wait(
                              Completer<void>().future,
                              const Duration(seconds: 30),
                            );
                            return HealthStage.firstFrame;
                          },
                        ),
                      ),
                    );
                    focus.requestFocus();
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(started, isTrue);
        if (useBack) {
          unawaited(navigator.currentState!.maybePop());
        } else {
          await tester.tap(find.text('取消并返回'));
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(find.byType(SourceHealthPage), findsNothing);
        expect(focus.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
