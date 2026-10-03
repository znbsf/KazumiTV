import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/card/bangumi_history_card.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/history/history_page.dart';
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

Finder _card(int id) => find.byWidgetPredicate((widget) =>
    widget is BangumiHistoryCardV && widget.historyItem.bangumiItem.id == id);
FocusNode _focus(WidgetTester tester, int id) =>
    tester.widget<BangumiHistoryCardV>(_card(id)).focusNode!;
ScrollController _scroll(WidgetTester tester) => tester
    .widget<CustomScrollView>(find.descendant(
        of: find.byType(HistoryPage), matching: find.byType(CustomScrollView)))
    .controller!;

History _history(int id) =>
    History(focusItem(id), 2, '本地测试源', DateTime(2026, 9, 6), '', '第2集');

Future<FocusFixtureApp> _mount(WidgetTester tester, {int count = 8}) async {
  tester.view.physicalSize = const Size(960, 540);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final app =
      FocusFixtureApp(initialRoute: '/tab/history/', historyCount: count);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  return app;
}

Future<void> _open(WidgetTester tester, int id) async {
  _focus(tester, id).requestFocus();
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.select);
  await tester.pumpAndSettle();
  expect(find.text('续播路由：仅验证参数，不是真实视频'), findsOneWidget);
}

Future<void> _back(WidgetTester tester) async {
  await rootNavigatorKey.currentState!.maybePop();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  setUpAll(() async {
    temporary = await Directory.systemTemp.createTemp('kazumi_history_return_');
    PathProviderPlatform.instance = _Paths(temporary.path);
    Hive.init(temporary.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    await temporary.delete(recursive: true);
  });
  setUp(() {
    TvMode.setEnabledForTesting(true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.predidit.kazumi/tv_navigation'),
            (_) async => null);
  });
  tearDown(() => TvMode.setEnabledForTesting(false));

  testWidgets('history playback return preserves subject after reorder',
      (tester) async {
    final app = await _mount(tester);
    await _open(tester, 3);
    app.history.histories
        .replaceRange(0, 8, [1, 4, 3, 2, 5, 6, 7, 8].map(_history));
    await tester.pumpAndSettle();
    await _back(tester);
    expect(_focus(tester, 3).hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(app.playback.opened.last.bangumiItem.id, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history return restores independent viewport id and offset',
      (tester) async {
    final app = await _mount(tester, count: 40);
    final scroll = _scroll(tester);
    scroll.jumpTo(4 + 152 * 4 + 30);
    await tester.pumpAndSettle();
    _focus(tester, 12).requestFocus();
    await tester.pumpAndSettle();
    final anchorTop = tester.getTopLeft(_card(9)).dy;
    await _open(tester, 12);
    app.history.histories.insertAll(0, [_history(101), _history(102)]);
    await tester.pumpAndSettle();
    await _back(tester);
    expect(_focus(tester, 12).hasPrimaryFocus, isTrue);
    expect(tester.getTopLeft(_card(9)).dy, closeTo(anchorTop, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('history removed return uses viewport neighbor then empty action',
      (tester) async {
    final app = await _mount(tester);
    await _open(tester, 3);
    app.history.histories.removeWhere((entry) => entry.bangumiItem.id == 3);
    await tester.pumpAndSettle();
    await _back(tester);
    // Native ReturnViewport falls back from the saved first-visible anchor.
    expect(_focus(tester, 1).hasPrimaryFocus, isTrue);
    await _open(tester, 1);
    app.history.histories.clear();
    await tester.pumpAndSettle();
    await _back(tester);
    final action =
        tester.widget<TextButton>(find.widgetWithText(TextButton, '返回'));
    expect(action.focusNode?.hasPrimaryFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history return realizes a subject reordered beyond viewport',
      (tester) async {
    final app = await _mount(tester, count: 60);
    await _open(tester, 3);
    final selected = app.history.histories.removeAt(2);
    app.history.histories.add(selected);
    await tester.pumpAndSettle();
    await _back(tester);
    expect(_focus(tester, 3).hasPrimaryFocus, isTrue);
    expect(
        tester.getRect(_card(3)).overlaps(const Rect.fromLTWH(0, 0, 960, 540)),
        isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(app.playback.opened.last.bangumiItem.id, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history new navigation cancels a pending offscreen return',
      (tester) async {
    final app = await _mount(tester, count: 60);
    await _open(tester, 3);
    final selected = app.history.histories.removeAt(2);
    app.history.histories.add(selected);
    await tester.pumpAndSettle();
    await rootNavigatorKey.currentState!.maybePop();
    // Reveal the route, then send real navigation while lazy realization is
    // still pending. The new action owns focus and viewport from this point.
    await tester.pump();
    _focus(tester, 1).requestFocus();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    final chosen = FocusManager.instance.primaryFocus;
    final offset = _scroll(tester).offset;
    expect(chosen?.debugLabel, 'TV history more');
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, same(chosen));
    expect(_scroll(tester).offset, closeTo(offset, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'history detail return retains the same More action after reorder',
      (tester) async {
    final app = await _mount(tester);
    _focus(tester, 3).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final more = FocusManager.instance.primaryFocus;
    expect(more?.debugLabel, 'TV history more');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(app.openedInfoIds, [3]);
    app.history.histories
        .replaceRange(0, 8, [1, 4, 2, 3, 5, 6, 7, 8].map(_history));
    await tester.pumpAndSettle();
    await _back(tester);
    expect(FocusManager.instance.primaryFocus, same(more));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('历史操作'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(app.openedInfoIds, [3, 3]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history missing viewport anchor resets its stale pixel offset',
      (tester) async {
    final app = await _mount(tester, count: 40);
    final scroll = _scroll(tester);
    scroll.jumpTo(4 + 152 * 4 + 30);
    await tester.pumpAndSettle();
    await _open(tester, 12);
    app.history.histories.removeWhere((entry) => entry.bangumiItem.id == 9);
    await tester.pumpAndSettle();
    await _back(tester);
    final viewport = tester.getRect(find.descendant(
        of: find.byType(HistoryPage), matching: find.byType(CustomScrollView)));
    expect(_focus(tester, 12).hasPrimaryFocus, isTrue);
    expect(tester.getTopLeft(_card(10)).dy, closeTo(viewport.top, 1));
    expect(tester.takeException(), isNull);
  });
}
