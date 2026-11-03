import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobx/mobx.dart';
import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/my/my_controller.dart';
import 'package:kazumi/pages/player/episode_comments_picker.dart';
import 'package:kazumi/pages/player/tv_player_controls.dart';
import 'package:kazumi/pages/settings/danmaku/danmaku_shield_editor.dart';
import 'package:kazumi/pages/video/episode_selection_panel.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

class _Rules implements MyController {
  @override
  final shieldList = ObservableList.of(['a', 'b', 'c']);
  @override
  Future<bool> removeShieldList(String rule) async {
    runInAction(() => shieldList.remove(rule));
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() => TvMode.setEnabledForTesting(false));

  for (final selected in [false, true]) {
    testWidgets('P-6 initial focus prefers business/current item $selected',
        (tester) async {
      final firstFocus = FocusNode();
      final currentFocus = FocusNode();
      addTearDown(firstFocus.dispose);
      addTearDown(currentFocus.dispose);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
        body: TvPlayerSettingsPanel(
            title: selected ? '播放速度' : '设置',
            onBack: () {},
            children: [
              TvPlayerAction(
                  label: 'first', focusNode: firstFocus, onPressed: () {}),
              TvPlayerAction(
                  label: 'current',
                  focusNode: currentFocus,
                  selected: selected,
                  onPressed: () {}),
            ]),
      )));
      await tester.pumpAndSettle();
      expect((selected ? currentFocus : firstFocus).hasPrimaryFocus, isTrue);
      await key(tester, LogicalKeyboardKey.arrowUp);
      if (selected) await key(tester, LogicalKeyboardKey.arrowUp);
      expect(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<TvPlayerAction>()
              ?.label,
          selected ? '返回设置' : '返回播放');
    });
  }

  testWidgets('P-3 system Back closes road menu and restores anchor',
      (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        home: Scaffold(
          body: SizedBox(
              width: 400,
              child: EpisodeSelectionPanel(
                title: 'test',
                roads: List.generate(
                    2,
                    (i) => Road(
                        name: 'road$i',
                        data: ['url$i'],
                        identifier: ['episode$i'])),
                selectedRoad: 1,
                selectedEpisode: 1,
                downloads: const {},
                onEpisodeSelected: (_, __) {},
              )),
        )));
    await tester.pumpAndSettle();
    final anchor = tester.widget<MenuAnchor>(find.byType(MenuAnchor));
    anchor.childFocusNode!.requestFocus();
    await tester.pump();
    await key(tester, LogicalKeyboardKey.enter);
    expect(find.byKey(const ValueKey('road-option-1')), findsOneWidget);
    await nav.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
    expect(find.byType(EpisodeSelectionPanel), findsOneWidget);
    expect(anchor.childFocusNode!.hasPrimaryFocus, isTrue);
  });

  testWidgets(
      'P-12 picker reveals and focuses a distant current episode; cancel returns',
      (tester) async {
    final anchor = FocusNode();
    addTearDown(anchor.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                    focusNode: anchor,
                    autofocus: true,
                    child: const Text('切换分集'),
                    onPressed: () => showDialog<int>(
                        context: context,
                        builder: (_) => EpisodeCommentsPicker(
                            episodes: List.generate(
                                150,
                                (i) => EpisodeInfo(
                                    id: i + 1,
                                    episode: i + 1,
                                    type: 0,
                                    name: 'episode ${i + 1}',
                                    nameCn: '')),
                            selectedEpisode: 130)),
                  ),
                ))));
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.enter);
    expect(find.text('EP 130'), findsOneWidget);
    expect(
        Focus.of(tester.element(find.text('EP 130'))).hasPrimaryFocus, isTrue);
    final rect = tester.getRect(find.text('EP 130'));
    expect(rect.top, greaterThan(0));
    expect(rect.bottom, lessThan(600));
    await key(tester, LogicalKeyboardKey.escape);
    expect(find.byType(EpisodeCommentsPicker), findsNothing);
    expect(anchor.hasPrimaryFocus, isTrue);
  });

  testWidgets('P-12 non-TV picker retains its original initial scroll',
      (tester) async {
    TvMode.setEnabledForTesting(false);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EpisodeCommentsPicker(
      episodes: List.generate(
          150,
          (i) => EpisodeInfo(
              id: i + 1, episode: i + 1, type: 0, name: '', nameCn: '')),
      selectedEpisode: 130,
    ))));
    await tester.pumpAndSettle();
    expect(find.text('EP 1'), findsOneWidget);
    expect(find.text('EP 130'), findsNothing);
    expect(
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
        0);
  });

  testWidgets(
      'P-14 deleting middle/last/only rule hands focus to adjacent/add entry',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: DanmakuShieldEditor(controller: _Rules()))));
    await tester.pumpAndSettle();
    Finder remove(String rule) => find.descendant(
        of: find.ancestor(of: find.text(rule), matching: find.byType(ListTile)),
        matching: find.byType(IconButton));
    Focus.of(tester.element(find.byIcon(Icons.close_rounded).at(1)))
        .requestFocus();
    final removedFocus = tester.widget<IconButton>(remove('b')).focusNode!;
    await tester.pump();
    await key(tester, LogicalKeyboardKey.enter);
    expect(find.text('b'), findsNothing);
    expect(() => removedFocus.addListener(() {}), throwsAssertionError,
        reason: 'removed rule nodes are disposed after the row unmounts');
    expect(tester.widget<IconButton>(remove('c')).focusNode?.hasPrimaryFocus,
        isTrue);
    await key(tester, LogicalKeyboardKey.enter);
    expect(tester.widget<IconButton>(remove('a')).focusNode?.hasPrimaryFocus,
        isTrue);
    await key(tester, LogicalKeyboardKey.enter);
    expect(find.text('还没有屏蔽规则'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Shield rule entry');
  });
}
