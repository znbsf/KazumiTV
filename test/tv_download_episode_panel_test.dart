import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobx/mobx.dart';
import 'package:kazumi/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:kazumi/bean/widget/tv_player_side_panel.dart';
import 'package:kazumi/bean/widget/tv_visuals.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/download/download_episode_sheet.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'support/tv_focus_fixtures.dart' show focusItem;

class _Downloads implements DownloadController {
  @override
  DownloadRecord? getRecord(int bangumiId, String pluginName) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Video implements VideoPageController {
  @override
  final BangumiItem bangumiItem = focusItem(1);
  @override
  final Plugin currentPlugin = Plugin.fromJson({'name': 'offline-fixture'});
  @override
  final roadList = ObservableList.of([
    Road(name: 'line', data: List.generate(60, (i) => '/$i'),
        identifier: List.generate(60, (i) => '第 ${i + 1} 集')),
  ]);
  @override
  VideoEpisodeSelection get playbackEpisode =>
      const VideoEpisodeSelection(episode: 1, road: 0);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  tearDown(() => TvMode.setEnabledForTesting(false));

  for (final tv in [true, false]) {
    for (final size in [const Size(960, 540), const Size(1280, 720)]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('download TV=$tv at $size / $scale uses correct content height',
            (tester) async {
          TvMode.setEnabledForTesting(tv);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final video = _Video();
          await tester.pumpWidget(ModularApp(
            module: createModule(register: (c) =>
                c.addInstance<DownloadController>(_Downloads())),
            child: MaterialApp(
              theme: tv ? TvVisuals.theme(ThemeData.dark()) : ThemeData(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Builder(builder: (context) => Scaffold(body: TextButton(
                onPressed: () => showAdaptiveBottomSheet<void>(
                  context: context,
                  builder: (_) => DownloadEpisodeSheet(
                      road: 0, videoPageController: video),
                ),
                child: const Text('Open'),
              ))),
            ),
          ));
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          if (tv) {
            expect(find.byType(DraggableScrollableSheet), findsNothing);
            final panel = tester.getRect(find.byType(TvPlayerSidePanel));
            final sheet = tester.getRect(find.byType(DownloadEpisodeSheet));
            expect(sheet, panel);
            expect(sheet.height, size.height);
            final grid = tester.getRect(find.byType(GridView));
            expect(grid.height, greaterThan(size.height * .6));
            expect(grid.bottom, lessThan(size.height));
            // A remote can select an episode, scroll and reach bottom actions.
            Focus.of(tester.element(find.text('第 1 集'))).requestFocus();
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(find.text('下载 1 集'), findsOneWidget);
            final scroll = tester.widget<GridView>(find.byType(GridView)).controller!;
            scroll.jumpTo(scroll.position.maxScrollExtent);
            await tester.pumpAndSettle();
            expect(find.text('第 60 集'), findsOneWidget);
          } else {
            final sheet = tester.widget<DraggableScrollableSheet>(
                find.byType(DraggableScrollableSheet));
            expect(sheet.expand, isFalse);
            expect(sheet.initialChildSize, greaterThanOrEqualTo(.6));
            expect(sheet.initialChildSize, lessThan(1));
            expect(find.byType(TvPlayerSidePanel), findsNothing);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
