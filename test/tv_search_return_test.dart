import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/widget/tv_focusable_surface.dart';
import 'package:kazumi/bean/widget/tv_search_entry.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/tv_focus_fixtures.dart';

class _SearchReturnPaths extends PathProviderPlatform {
  _SearchReturnPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Finder _resultSurface(int id) => find
    .ancestor(
      of: find.text('本地测试番剧 $id'),
      matching: find.byType(TvFocusableSurface),
    )
    .last;

// This uses the public Focus tree rather than a production-only test hook or
// relying on the optional focusNode field being supplied by the implementation.
FocusNode _resultFocus(WidgetTester tester, int id) => Focus.of(
      tester.element(find
          .descendant(
            of: _resultSurface(id),
            matching: find.byType(AnimatedScale),
          )
          .first),
    );

Future<FocusFixtureApp> _mountSearch(WidgetTester tester) async {
  tester.view.physicalSize = const Size(960, 540);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final app = FocusFixtureApp(initialRoute: '/search/');
  app.search.preserveResults = true;
  app.search.hasMoreSearchResults = false;
  app.search.bangumiList
      .addAll(List.generate(6, (index) => focusItem(index + 1)));
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.select);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('tv-search-editor')), 'test');
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
  return app;
}

Future<void> _openResult(WidgetTester tester, int id) async {
  _resultFocus(tester, id).requestFocus();
  await tester.pumpAndSettle();
  expect(_resultFocus(tester, id).hasPrimaryFocus, isTrue);
  await tester.sendKeyEvent(LogicalKeyboardKey.select);
  await tester.pumpAndSettle();
  expect(find.text('详情路由：本地测试'), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporaryDirectory;

  setUpAll(() async {
    temporaryDirectory =
        await Directory.systemTemp.createTemp('kazumi_search_return_');
    PathProviderPlatform.instance = _SearchReturnPaths(temporaryDirectory.path);
    Hive.init(temporaryDirectory.path);
    await GStorage.init();
  });

  tearDownAll(() async {
    await Hive.close();
    await temporaryDirectory.delete(recursive: true);
  });

  setUp(() {
    TvMode.setEnabledForTesting(true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.predidit.kazumi/tv_navigation'),
      (_) async => null,
    );
  });

  tearDown(() => TvMode.setEnabledForTesting(false));

  testWidgets(
      'TV search detail return keeps the same subject after result reordering',
      (tester) async {
    final app = await _mountSearch(tester);
    await _openResult(tester, 3);
    expect(app.openedInfoIds.last, 3);

    // Both cards remain in the same visible row. The route changes only the
    // order, so a failure cannot be excused as an offscreen realization issue.
    app.search.bangumiList.replaceRange(
      0,
      app.search.bangumiList.length,
      [1, 3, 2, 4, 5, 6].map(focusItem),
    );
    await tester.pumpAndSettle();
    await rootNavigatorKey.currentState!.maybePop();
    await tester.pumpAndSettle();

    expect(_resultFocus(tester, 3).hasPrimaryFocus, isTrue,
        reason: 'Returning should follow subject 3, not its old grid index');
    expect(_resultFocus(tester, 2).hasPrimaryFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(app.openedInfoIds.last, 3,
        reason: 'The next OK must open the originally selected subject');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'TV search return falls back to a neighbor or an actionable empty state',
      (tester) async {
    final app = await _mountSearch(tester);
    await _openResult(tester, 3);
    app.search.bangumiList.removeWhere((item) => item.id == 3);
    await tester.pumpAndSettle();
    await rootNavigatorKey.currentState!.maybePop();
    await tester.pumpAndSettle();

    expect(find.text('本地测试番剧 3'), findsNothing);
    expect(_resultFocus(tester, 4).hasPrimaryFocus, isTrue,
        reason: 'The old position now contains the next surviving subject');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(app.openedInfoIds.last, 4);

    app.search.bangumiList.clear();
    await tester.pumpAndSettle();
    await rootNavigatorKey.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('没有找到番剧'), findsOneWidget);
    final emptyAction =
        tester.widget<TextButton>(find.widgetWithText(TextButton, '调整筛选'));
    expect(emptyAction.focusNode?.hasPrimaryFocus, isTrue,
        reason: 'An empty return must focus a surviving action');
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV search return realizes a subject moved beyond the viewport',
      (tester) async {
    final app = await _mountSearch(tester);
    app.search.bangumiList
        .addAll(List.generate(54, (index) => focusItem(index + 7)));
    await tester.pumpAndSettle();
    await _openResult(tester, 3);

    app.search.bangumiList.replaceRange(
      0,
      app.search.bangumiList.length,
      [...List.generate(60, (index) => index + 1).where((id) => id != 3), 3]
          .map(focusItem),
    );
    await tester.pumpAndSettle();
    await rootNavigatorKey.currentState!.maybePop();
    await tester.pumpAndSettle();

    expect(_resultFocus(tester, 3).hasPrimaryFocus, isTrue);
    final rectangle = tester.getRect(_resultSurface(3));
    expect(rectangle.bottom, greaterThan(0));
    expect(rectangle.top, lessThan(540));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(app.openedInfoIds.last, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV search new query cancels a pending detail return',
      (tester) async {
    final app = await _mountSearch(tester);
    final entry = tester.widget<TvSearchEntry>(find.byType(TvSearchEntry));
    final entryFocus = tester
        .widget<TvFocusableSurface>(find.byKey(const Key('tv-search-entry')))
        .focusNode!;
    await _openResult(tester, 3);

    await rootNavigatorKey.currentState!.maybePop();
    // Submit through the real entry's public UI callback before the old
    // route completion/realization frames settle, not a state test hook.
    app.search.preserveResults = false;
    entry.onSubmitted('new query');
    entryFocus.requestFocus();
    await tester.pumpAndSettle();

    expect(app.search.submitted, 'new query');
    expect(entry.controller.text, 'new query');
    expect(find.text('本地测试番剧 99'), findsOneWidget);
    expect(find.text('本地测试番剧 3'), findsNothing);
    expect(entryFocus.hasPrimaryFocus, isTrue,
        reason: 'The old return must not take focus from the new query entry');
    expect(_resultFocus(tester, 99).hasPrimaryFocus, isFalse);
    expect(tester.takeException(), isNull);
  });
}
