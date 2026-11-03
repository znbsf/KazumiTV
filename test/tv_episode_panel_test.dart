import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/episode_tile.dart';
import 'package:kazumi/bean/widget/tv_visuals.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/video/episode_selection_panel.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

void main() {
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() => TvMode.setEnabledForTesting(false));

  for (final viewport in [const Size(960, 540), const Size(1280, 720)]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('TV episode full name follows focus at $viewport text $scale',
          (tester) async {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final labels = List.generate(12,
            (i) => '第${i + 1}集：这是需要完整阅读的长剧集名称，包含后半段的剧情标题');
        final selected = <List<int>>[];
        await tester.pumpWidget(MaterialApp(
            theme: TvVisuals.theme(ThemeData.dark()),
            home: MediaQuery(
                data: MediaQueryData(
                    size: viewport, textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                    body: Align(
                        alignment: Alignment.centerRight,
                        child: SizedBox(
                            width: viewport.width * .42,
                            child: EpisodeSelectionPanel(
                              title: '剧集列表',
                              roads: [Road(
                                  name: '本地',
                                  data: List.generate(12, (i) => '$i'),
                                  identifier: labels)],
                              selectedRoad: 0,
                              selectedEpisode: 1,
                              isOffline: true,
                              downloads: const {},
                              onEpisodeSelected: (episode, road) =>
                                  selected.add([episode, road]),
                            )))))));
        await tester.pumpAndSettle();
        final grid = tester.widget<GridView>(find.byType(GridView));
        expect((grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount, 4);
        Finder fullName(String name) => find.byWidgetPredicate(
            (w) => w is Text && w.data == name && w.maxLines == null);
        final tile = find.byKey(const ValueKey('0:1'));
        final before = tester.getRect(tile);
        final node = tester.widget<EpisodeTile>(tile).focusNode!;
        node.requestFocus();
        await tester.pumpAndSettle();
        expect(fullName(labels[0]), findsOneWidget);
        expect(node.hasPrimaryFocus, isTrue);
        expect(tester.getRect(tile), before);
        final rect = tester.getRect(fullName(labels[0]));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(viewport.width));
        expect(rect.bottom, lessThanOrEqualTo(viewport.height));
        expect(tester.widget<Text>(fullName(labels[0])).overflow, isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(fullName(labels[0]), findsNothing);
        expect(fullName(labels[1]), findsOneWidget);
        expect(tester.widget<EpisodeTile>(find.byKey(const ValueKey('0:2')))
            .focusNode!.hasPrimaryFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        expect(selected, [[2, 0]]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(fullName(labels[1]), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('TV road menu focuses choices and supports up down and confirm',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: EpisodeSelectionPanel(
            title: '线路测试',
            roads: List.generate(
                2,
                (i) =>
                    Road(name: '线路$i', data: ['url$i'], identifier: ['剧集$i'])),
            selectedRoad: 0,
            selectedEpisode: 1,
            downloads: const {},
            onEpisodeSelected: (_, __) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final anchor = tester.widget<MenuAnchor>(find.byType(MenuAnchor));
    anchor.childFocusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    bool focused(int index) =>
        tester
            .widget<MenuItemButton>(find.byKey(ValueKey('road-option-$index')))
            .focusNode
            ?.hasFocus ==
        true;
    expect(focused(0), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focused(1), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(focused(0), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('road-option-0')), findsNothing);
    expect(find.text('剧集1'), findsOneWidget);
    expect(anchor.childFocusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(focused(1), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('road-option-1')), findsNothing);
    expect(anchor.childFocusNode!.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'TV panel locates recycled episode, wraps ragged row and activates exact road',
      (tester) async {
    final key = GlobalKey<EpisodeSelectionPanelState>();
    final selected = <List<int>>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
      width: 400,
      height: 460,
      child: EpisodeSelectionPanel(
        key: key,
        title: '离线选集布局验证',
        roads: [
          Road(
              name: '本地',
              data: List.generate(99, (i) => '$i'),
              identifier: List.generate(99, (i) => '第${i + 1}集'))
        ],
        selectedRoad: 0,
        selectedEpisode: 98,
        isOffline: true,
        downloads: const {},
        onEpisodeSelected: (episode, road) => selected.add([episode, road]),
      ),
    ))));
    await tester.pumpAndSettle();
    final reveal = key.currentState!.revealCurrentEpisode();
    await tester.pumpAndSettle();
    await reveal;
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TV episode 0:98');
    final current = FocusManager.instance.primaryFocus!;
    expect(current.rect.bottom, lessThanOrEqualTo(460));
    for (final key in [
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowRight
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TV episode 0:97');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(selected, [
      [97, 0]
    ]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TV episode 0:1');
    expect(find.byType(EpisodeTile), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
