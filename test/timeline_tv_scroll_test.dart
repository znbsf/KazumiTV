import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/card/bangumi_timeline_card.dart';
import 'package:kazumi/bean/widget/tv_focus_navigation.dart';
import 'package:kazumi/pages/timeline/timeline_controller.dart';
import 'package:kazumi/pages/timeline/timeline_page.dart';
import 'package:kazumi/repositories/collect_repository.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'support/tv_focus_fixtures.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  setUpAll(() async {
    temporary =
        await Directory.systemTemp.createTemp('kazumi_timeline_scroll_');
    PathProviderPlatform.instance = _Paths(temporary.path);
    Hive.init(temporary.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    await temporary.delete(recursive: true);
  });
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() => TvMode.setEnabledForTesting(false));

  testWidgets('timeline remote returns to first row after virtualized scroll',
      (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TimelineController(CollectRepository());
    controller.bangumiCalendar.addAll(List.generate(
        7, (day) => List.generate(40, (i) => focusItem(day * 100 + i))));
    await tester.pumpWidget(MaterialApp(
        home: FocusTraversalGroup(
            policy: TvLoopTraversalPolicy(),
            child: Padding(
                padding: const EdgeInsets.only(top: 64),
                child: TimelinePage(controller: controller)))));
    await tester.pumpAndSettle();
    final firstId = (DateTime.now().weekday - 1) * 100;
    Finder card(int id) => find.byWidgetPredicate(
        (w) => w is BangumiTimelineCard && w.bangumiItem.id == id);
    final originalTop = tester.getTopLeft(card(firstId)).dy;
    Focus.of(tester.element(find
            .descendant(of: card(firstId), matching: find.byType(Card))
            .first))
        .requestFocus();
    await tester.pumpAndSettle();
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
    }
    expect(card(firstId), findsOneWidget,
        reason: 'first row must be reachable after it was recycled');
    expect(tester.getTopLeft(card(firstId)).dy, closeTo(originalTop, 1),
        reason: 'first row must return below the pinned weekday header');
    final firstFocus = Focus.of(tester.element(
        find.descendant(of: card(firstId), matching: find.byType(Card)).first));
    expect(firstFocus.hasPrimaryFocus, isTrue);
    for (var round = 0; round < 3; round++) {
      for (final key in [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowUp
      ]) {
        await tester.sendKeyDownEvent(key);
        await tester.pump(const Duration(milliseconds: 30));
        for (var i = 0; i < 11; i++) {
          await tester.sendKeyRepeatEvent(key);
          await tester.pump(const Duration(milliseconds: 30));
        }
        await tester.sendKeyUpEvent(key);
        await tester.pumpAndSettle();
      }
      expect(card(firstId), findsOneWidget);
      expect(tester.getTopLeft(card(firstId)).dy, closeTo(originalTop, 1));
      expect(
          Focus.of(tester.element(find
                  .descendant(of: card(firstId), matching: find.byType(Card))
                  .first))
              .hasPrimaryFocus,
          isTrue);
    }
    // Pointer dragging and a weekday round trip must not create another
    // scroll origin. Exercise the actual page, not a stand-alone card grid.
    final grid = find.byType(CustomScrollView).hitTestable();
    await tester.drag(grid, const Offset(0, -650));
    await tester.pumpAndSettle();
    final tabs = DefaultTabController.of(tester.element(find.byType(TabBar)));
    final day = tabs.index;
    tabs.animateTo((day + 1) % 7);
    await tester.pumpAndSettle();
    tabs.animateTo(day);
    await tester.pumpAndSettle();
    for (var i = 0; i < 8; i++) {
      await tester.drag(
          find.byType(CustomScrollView).hitTestable(), const Offset(0, 650));
      await tester.pumpAndSettle();
    }
    expect(tester.getTopLeft(card(firstId)).dy, closeTo(originalTop, 1));
    final position = tester
        .state<ScrollableState>(find
            .descendant(
                of: find.byType(CustomScrollView).hitTestable(),
                matching: find.byType(Scrollable))
            .first)
        .position;
    expect(position.pixels, closeTo(position.minScrollExtent, .01));
    final pointer =
        tester.getCenter(find.byType(CustomScrollView).hitTestable());
    await tester.sendEventToBinding(PointerScrollEvent(
        position: pointer, scrollDelta: const Offset(0, 800)));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(position.minScrollExtent));
    await tester.sendEventToBinding(PointerScrollEvent(
        position: pointer, scrollDelta: const Offset(0, -5000)));
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(position.minScrollExtent, .01));
    expect(tester.getTopLeft(card(firstId)).dy, closeTo(originalTop, 1));
    expect(tester.takeException(), isNull);
  });
}
