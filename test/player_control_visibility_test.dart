import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobx/mobx.dart';
import 'package:kazumi/pages/player/player_control_visibility.dart';

void main() {
  testWidgets('hidden action strip restores its scroll offset after remount',
      (tester) async {
    final animation = AnimationController(vsync: tester, value: 1);
    addTearDown(animation.dispose);
    final bucket = PageStorageBucket();
    Widget app(bool visible) => MaterialApp(
        home: PageStorage(
            bucket: bucket,
            child: SizedBox(
                width: 300,
                child: PlayerControlVisibility(
                  visible: visible,
                  locked: false,
                  disableAnimations: true,
                  animation: animation,
                  child: SingleChildScrollView(
                      key: const PageStorageKey('actions'),
                      scrollDirection: Axis.horizontal,
                      child: Row(
                          children: List.generate(
                              30,
                              (i) => SizedBox(
                                  width: 100, child: Text('action $i'))))),
                ))));
    await tester.pumpWidget(app(true));
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    final before =
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;
    expect(before, greaterThan(0));
    await tester.pumpWidget(app(false));
    await tester.pumpWidget(app(true));
    expect(
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
        before);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'hidden controls stop observing ticks and reopen at latest position',
      (tester) async {
    final animation = AnimationController(
        vsync: tester, value: 1, duration: const Duration(milliseconds: 200));
    final focus = FocusNode();
    addTearDown(animation.dispose);
    addTearDown(focus.dispose);
    final position = Observable(10);
    var builds = 0;
    Widget app(bool visible,
            {bool locked = false, bool noAnimations = false}) =>
        MaterialApp(
            home: Scaffold(
                body: PlayerControlVisibility(
          visible: visible,
          locked: locked,
          disableAnimations: noAnimations,
          animation: animation,
          child: Observer(builder: (_) {
            builds++;
            return TextButton(
                focusNode: focus,
                onPressed: () {},
                child: Text('position ${position.value}'));
          }),
        )));
    await tester.pumpWidget(app(true));
    animation.reverse();
    await tester.pumpWidget(app(false));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('position 10'), findsOneWidget);
    await tester.pumpAndSettle();
    final hiddenBuilds = builds;
    for (var i = 11; i <= 30; i++) {
      runInAction(() => position.value = i);
      await tester.pump();
    }
    expect(builds, hiddenBuilds);
    expect(find.byType(TextButton), findsNothing);
    animation.forward();
    await tester.pumpWidget(app(true));
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(find.text('position 30'), findsOneWidget);
    expect(focus.hasPrimaryFocus, isTrue);
    animation.reverse();
    await tester.pumpWidget(app(false));
    await tester.pump(const Duration(milliseconds: 50));
    animation.forward();
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    expect(find.text('position 30'), findsOneWidget);
    await tester.pumpWidget(app(true, locked: true));
    expect(find.byType(TextButton), findsNothing);
    await tester.pumpWidget(app(false, noAnimations: true));
    expect(find.byType(TextButton), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
