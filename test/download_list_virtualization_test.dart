import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:mobx/mobx.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/download/download_page.dart';
import 'package:kazumi/pages/download/download_widgets.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/storage/storage.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

DownloadRecord record(int count, {double progress = .1}) => DownloadRecord(
    1,
    'Long show',
    '',
    'test',
    {
      for (var i = count; i >= 1; i--)
        i: DownloadEpisode(i, 'Episode $i', 0, DownloadStatus.paused, progress,
            100, 10, '', '', '', null, '', 0, 'url/$i')
    },
    DateTime.utc(2026));

class _Downloads implements DownloadController {
  _Downloads(int count) : snapshot = Observable(record(count));
  final Observable<DownloadRecord> snapshot;
  final resumed = <int>[];
  @override
  final recordKeys = ObservableList.of(['test_1']);
  @override
  void refreshRecords() {}
  @override
  DownloadRecord? getRecordSnapshot(String key) => snapshot.value;
  @override
  double getSpeed(int id, String plugin, int episode) => 0;
  @override
  Future<void> retryDownload(
      {required int bangumiId,
      required String pluginName,
      required int episodeNumber}) async {
    resumed.add(episodeNumber);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late PathProviderPlatform original;
  setUpAll(() async {
    temporary = await Directory.systemTemp.createTemp('download_list_');
    original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(temporary.path);
    Hive.init(temporary.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = original;
    await temporary.delete(recursive: true);
  });
  for (final count in [300, 1000]) {
    testWidgets(
        '$count episodes build only visible rows and preserve actions after progress',
        (tester) async {
      TvMode.setEnabledForTesting(true);
      addTearDown(() => TvMode.setEnabledForTesting(false));
      final downloads = _Downloads(count);
      await tester
          .pumpWidget(MaterialApp(home: DownloadPage(controller: downloads)));
      await tester.pumpAndSettle();
      expect(find.byType(DownloadEpisodeTile).evaluate().length, lessThan(40));
      expect(find.text('Episode 1'), findsOneWidget);
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('Episode 30'), 400,
          scrollable: scrollable);
      await tester.pumpAndSettle();
      final offset = tester.state<ScrollableState>(scrollable).position.pixels;
      final row = find.ancestor(
          of: find.text('Episode 30'),
          matching: find.byType(DownloadEpisodeTile));
      final resume = find.descendant(of: row, matching: find.byTooltip('继续'));
      final button = tester.element(
          find.descendant(of: resume, matching: find.byType(Icon)).first);
      final focus = Focus.of(button);
      focus.requestFocus();
      await tester.pump();
      runInAction(() => downloads.snapshot.value = record(count, progress: .5));
      await tester.pump();
      expect(tester.state<ScrollableState>(scrollable).position.pixels, offset);
      expect(find.byType(DownloadEpisodeTile).evaluate().length, lessThan(40));
      expect(focus.hasPrimaryFocus, isTrue);
      runInAction(() => downloads.snapshot.value = record(count, progress: .5)
        ..episodes.remove(1));
      await tester.pump();
      expect(focus.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(downloads.resumed, [30]);
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Long show'));
      await tester.pumpAndSettle();
      expect(find.byType(DownloadEpisodeTile), findsNothing);
      await tester.tap(find.text('Long show'));
      await tester.pumpAndSettle();
      expect(find.text('Episode 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
