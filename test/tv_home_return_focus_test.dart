import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/bean/widget/tv_focusable_surface.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/popular/popular_page.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/tv_focus_fixtures.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Finder _card(int id) => find.byWidgetPredicate(
    (widget) => widget is BangumiCardV && widget.bangumiItem.id == id);
FocusNode _focus(WidgetTester tester, int id) =>
    tester.widget<BangumiCardV>(_card(id)).focusNode!;
Finder get _view => find.descendant(
    of: find.byType(PopularPage), matching: find.byType(CustomScrollView));
ScrollController _scroll(WidgetTester tester) =>
    tester.widget<CustomScrollView>(_view).controller!;

Future<FocusFixtureApp> _mount(WidgetTester tester, {int count = 60}) async {
  tester.view.physicalSize = const Size(960, 540);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final app = FocusFixtureApp(count: count);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  return app;
}

Future<void> _open(WidgetTester tester, int id) async {
  _focus(tester, id).requestFocus();
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.select);
  await tester.pumpAndSettle();
  expect(find.text('详情路由：本地测试'), findsOneWidget);
}

Future<void> _back(WidgetTester tester) async {
  await rootNavigatorKey.currentState!.maybePop();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  setUpAll(() async {
    temporary = await Directory.systemTemp.createTemp('kazumi_home_return_');
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

  testWidgets(
      'home detail return follows subject while channel numbers reorder',
      (tester) async {
    final app = await _mount(tester);
    await _open(tester, 3);
    app.popular.trendList.replaceRange(0, 6, [1, 3, 2, 4, 5, 6].map(focusItem));
    await tester.pumpAndSettle();
    await _back(tester);
    expect(_focus(tester, 3).hasPrimaryFocus, isTrue);
    expect(tester.widget<BangumiCardV>(_card(3)).channelNumber, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(app.openedInfoIds, [3, 3]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home return retains viewport anchor and its pixel offset',
      (tester) async {
    final app = await _mount(tester);
    final stride = tester.getSize(_card(1)).height + StyleString.cardSpace - 2;
    _scroll(tester).jumpTo(stride * 3 + 30);
    await tester.pumpAndSettle();
    // Row four is fully visible; row three is partially hidden by the fixed
    // category toolbar. Focus and the first visible poster have distinct ids.
    _focus(tester, 25).requestFocus();
    await tester.pumpAndSettle();
    final anchorTop = tester.getTopLeft(_card(19)).dy;
    await _open(tester, 25);
    app.popular.trendList
        .insertAll(0, List.generate(6, (i) => focusItem(101 + i)));
    await tester.pumpAndSettle();
    await _back(tester);
    expect(_focus(tester, 25).hasPrimaryFocus, isTrue);
    expect(tester.getTopLeft(_card(19)).dy, closeTo(anchorTop, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'home missing subject returns to viewport neighbor then empty category',
      (tester) async {
    final app = await _mount(tester);
    await _open(tester, 3);
    app.popular.trendList.removeWhere((item) => item.id == 3);
    await tester.pumpAndSettle();
    await _back(tester);
    expect(_focus(tester, 1).hasPrimaryFocus, isTrue);
    await _open(tester, 1);
    app.popular.trendList.clear();
    await tester.pumpAndSettle();
    await _back(tester);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TV category 热门番组');
    expect(tester.takeException(), isNull);
  });

  testWidgets('home return realizes subject moved beyond its cached rows',
      (tester) async {
    final app = await _mount(tester);
    await _open(tester, 3);
    final selected = app.popular.trendList.removeAt(2);
    app.popular.trendList.add(selected);
    await tester.pumpAndSettle();
    await _back(tester);
    expect(_focus(tester, 3).hasPrimaryFocus, isTrue);
    expect(
        tester.getRect(_card(3)).overlaps(const Rect.fromLTWH(0, 88, 960, 452)),
        isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(app.openedInfoIds, [3, 3]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home category selection cancels a pending old detail return',
      (tester) async {
    final app = await _mount(tester);
    final tag = defaultAnimeTags.first;
    final tab = tester.widget<TvFocusableSurface>(find.ancestor(
        of: find.text(tag), matching: find.byType(TvFocusableSurface)));
    await _open(tester, 3);
    await rootNavigatorKey.currentState!.maybePop();
    tab.onPressed();
    tab.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    expect(app.popular.currentTag, tag);
    expect(tab.focusNode!.hasPrimaryFocus, isTrue);
    expect(tester.takeException(), isNull);
  });
}
