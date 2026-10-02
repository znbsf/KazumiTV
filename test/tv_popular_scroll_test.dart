import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/bean/widget/tv_focusable_surface.dart';
import 'package:kazumi/bean/widget/tv_app_shell.dart';
import 'package:kazumi/bean/widget/tv_artwork.dart';
import 'package:kazumi/services/player/low_memory_mode.dart';
import 'package:kazumi/pages/popular/popular_page.dart';
import 'package:kazumi/pages/popular/tv_popular_controller.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/platform/tv_channel_input.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/services/performance/tv_input_lifecycle.dart';
import 'package:kazumi/utils/constants.dart';
import 'support/tv_focus_fixtures.dart';

class _TempPaths extends PathProviderPlatform {
  _TempPaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Finder _poster(int number) => find
    .byWidgetPredicate((w) => w is BangumiCardV && w.channelNumber == number);

List<Map<String, Object>> _subjects(int first, int count) => List.generate(
    count,
    (index) => {
          'id': first + index,
          'name': 'offline subject ${first + index}',
          'summary': 'offline pagination fixture',
          'rating': {'rank': 1, 'score': 7.0, 'total': 1},
          'images': <String, String>{},
        });

void _expectVisibleFocus(WidgetTester tester, int number) {
  final finder = _poster(number);
  expect(finder, findsOneWidget, reason: 'poster $number must be laid out');
  expect(tester.widget<BangumiCardV>(finder).focusNode!.hasPrimaryFocus, isTrue,
      reason: 'poster $number owns focus');
  final rect = tester.getRect(finder);
  final viewport = tester.getRect(find.descendant(
      of: find.byType(PopularPage), matching: find.byType(CustomScrollView)));
  final header = tester.getRect(find.descendant(
      of: find.byType(PopularPage), matching: find.byType(AppBar)));
  expect(rect.top, greaterThanOrEqualTo(header.bottom - 0.5),
      reason: 'poster $number must not hide behind the pinned categories');
  expect(rect.bottom, lessThanOrEqualTo(viewport.bottom + 0.5),
      reason: 'poster $number must remain fully visible');
  expect(tester.takeException(), isNull);
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  late Directory temp;
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('kazumi_popular_scroll_');
    PathProviderPlatform.instance = _TempPaths(temp.path);
    Hive.init(temp.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });
  setUp(() {
    TvMode.setEnabledForTesting(true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.predidit.kazumi/tv_navigation'),
            (_) async => null);
  });
  tearDown(() {
    DioFactory.reset();
    tvChannelInputController.cancel();
    TvMode.setEnabledForTesting(false);
  });

  Future<FocusFixtureApp> mount(WidgetTester tester,
      {Size size = const Size(960, 540),
      int count = 120,
      double textScale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = FocusFixtureApp(count: count, textScale: textScale);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    tester.widget<BangumiCardV>(_poster(1)).focusNode!.requestFocus();
    await tester.pumpAndSettle();
    return app;
  }

  testWidgets(
      'paced held vertical keys settle at 21 then 1 without release drift',
      (tester) async {
    var elapsed = 0;
    final life = TvInputLifecycle(() => elapsed)..install();
    addTearDown(life.dispose);
    await mount(tester, count: 40);
    life.start(0);
    Future<void> frames(int millis) async {
      for (var t = 0; t < millis; t += 10) {
        elapsed += 10000;
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    Future<void> hold(LogicalKeyboardKey key, int target) async {
      await tester.sendKeyDownEvent(key);
      await frames(450);
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyRepeatEvent(key);
        await frames(180);
      }
      await tester.sendKeyUpEvent(key);
      await frames(250);
      _expectVisibleFocus(tester, target);
      final state = tester.state<ScrollableState>(find
          .descendant(
              of: find.byType(CustomScrollView).first,
              matching: find.byType(Scrollable))
          .first);
      final offset = state.position.pixels;
      await frames(1250);
      _expectVisibleFocus(tester, target);
      expect(state.position.pixels, closeTo(offset, .01));
    }

    await hold(LogicalKeyboardKey.arrowDown, 21);
    await hold(LogicalKeyboardKey.arrowUp, 1);
    life.stop();
    final report = life.report();
    expect((report['appEvents'] as List).map((e) => e['type']), [
      'down',
      'repeat',
      'repeat',
      'repeat',
      'up',
      'down',
      'repeat',
      'repeat',
      'repeat',
      'up'
    ]);
    expect((report['catalogStart'] as Map)['columns'], 5);
    expect((report['logging'] as Map)['scrollComplete'], isTrue);
    expect((report['checkpoints'] as List).last['state']['pendingChannel'],
        isNull);
  });

  testWidgets('TV home shows a complete larger row and a following-row cue',
      (tester) async {
    await mount(tester);
    final viewport = tester.getRect(find.byType(CustomScrollView).first);
    final last = tester.getRect(_poster(5));
    expect(tester.getRect(_poster(6)).top, lessThan(viewport.bottom));
    expect(last.bottom, lessThanOrEqualTo(viewport.bottom - 3));
    final image =
        find.descendant(of: _poster(5), matching: find.byType(AspectRatio));
    expect(tester.widget<AspectRatio>(image.first).aspectRatio, 0.65);
    final badge = find.descendant(
      of: _poster(5),
      matching: find.byWidgetPredicate((widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).color ==
              Colors.black.withValues(alpha: 0.45)),
    );
    expect(badge, findsOneWidget,
        reason: 'The channel badge must leave the poster visible beneath it');
    expect(tester.takeException(), isNull);
  });

  testWidgets('cold data selects spotlight without moving navigation focus',
      (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tvArtworkController.select(null);
    final app = FocusFixtureApp(count: 0);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    final navigation = tester
        .widget<TvFocusableSurface>(find.byWidgetPredicate((widget) =>
            widget is TvFocusableSurface &&
            widget.focusNode?.debugLabel == 'TV function 3'))
        .focusNode!;
    navigation.requestFocus();
    await tester.pumpAndSettle();
    app.popular.trendList.addAll(List.generate(24, (i) => focusItem(101 + i)));
    await tester.pumpAndSettle();
    expect(navigation.hasPrimaryFocus, isTrue);
    expect(tvArtworkController.value?.id, 101);
    expect(find.text('仅供焦点验证'), findsOneWidget);

    tester.widget<BangumiCardV>(_poster(2)).focusNode!.requestFocus();
    await tester.pumpAndSettle();
    expect(tvArtworkController.value?.id, 102);
    navigation.requestFocus();
    await tester.pumpAndSettle();
    app.popular.trendList.add(focusItem(199));
    await tester.pumpAndSettle();
    expect(tvArtworkController.value?.id, 102,
        reason: 'Appending items keeps the current valid spotlight');
    app.popular.trendList
        .replaceRange(0, 25, List.generate(24, (i) => focusItem(301 + i)));
    await tester.pumpAndSettle();
    expect(navigation.hasPrimaryFocus, isTrue);
    expect(tvArtworkController.value?.id, 301,
        reason: 'A removed spotlight falls back to the new first item');
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV category strip reveals both directions without wrapping',
      (tester) async {
    final app = await mount(tester, size: const Size(854, 480));
    final tabs = find.byWidgetPredicate((w) =>
        w is TvFocusableSurface &&
        (w.focusNode?.debugLabel?.startsWith('TV category ') ?? false));
    final surfaces = tester.widgetList<TvFocusableSurface>(tabs).toList();
    final first = surfaces.first.focusNode!;
    first.requestFocus();
    await tester.pumpAndSettle();
    final viewport = tester.getRect(find.ancestor(
        of: tabs.first, matching: find.byType(SingleChildScrollView)));
    void expectCategory(int index) {
      expect(surfaces[index].focusNode!.hasPrimaryFocus, isTrue);
      final rect = tester.getRect(tabs.at(index));
      expect(rect.left, greaterThanOrEqualTo(viewport.left + 3));
      expect(rect.right, lessThanOrEqualTo(viewport.right - 3));
    }

    final queries = app.popular.queries;
    expectCategory(0);
    for (var i = 1; i < surfaces.length; i++) {
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expectCategory(i);
    }
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expectCategory(surfaces.length - 1);
    for (var i = surfaces.length - 2; i >= 0; i--) {
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      expectCategory(i);
    }
    expect(app.popular.currentTag, isEmpty);
    expect(app.popular.queries, queries,
        reason: 'Moving focus must not select or request a category');
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(FocusManager.instance.primaryFocus!.debugLabel, 'TV function 3');
    expect(
        tester
            .getRect(find.byWidgetPredicate((w) =>
                w is TvFocusableSurface &&
                w.focusNode?.debugLabel == 'TV function 3'))
            .center
            .dy,
        closeTo(tester.getRect(tabs.first).center.dy, 1));
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expectCategory(0);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expectCategory(1);
    expect(app.popular.currentTag, isEmpty);
    await _press(tester, LogicalKeyboardKey.select);
    expect(app.popular.currentTag, defaultAnimeTags.first);
    expect(app.popular.queries, queries + 1);
  });

  test('TV memory defaults on and preserves all explicit modes like mobile',
      () async {
    await GStorage.putSetting(SettingsKeys.lowMemoryPolicy, null);
    expect(LowMemoryMode.current, LowMemoryMode.always);
    await LowMemoryMode.auto.save();
    expect(LowMemoryMode.current, LowMemoryMode.auto);
    await LowMemoryMode.never.save();
    expect(LowMemoryMode.current, LowMemoryMode.never);
    TvMode.setEnabledForTesting(false);
    await LowMemoryMode.auto.save();
    expect(LowMemoryMode.current, LowMemoryMode.auto);
  });

  for (final size in [
    const Size(854, 480),
    const Size(960, 540),
    const Size(1280, 720)
  ]) {
    for (final textScale in [1.0, 1.25]) {
      testWidgets('offline home reveals every row both ways: $size/$textScale',
          (tester) async {
        final app = await mount(tester, size: size, textScale: textScale);
        // Real homepage, pinned categories and virtualized grid; no network.
        for (var row = 1; row <= 9; row++) {
          await _press(tester, LogicalKeyboardKey.arrowDown);
          _expectVisibleFocus(tester, row * 5 + 1);
        }
        for (var row = 8; row >= 0; row--) {
          await _press(tester, LogicalKeyboardKey.arrowUp);
          _expectVisibleFocus(tester, row * 5 + 1);
        }
        expect(app.popular.scrollOffset, lessThan(10));
      });
    }
  }

  testWidgets('horizontal movement does not recenter an already visible row',
      (tester) async {
    final app = await mount(tester);
    for (var i = 0; i < 3; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    await _press(tester, LogicalKeyboardKey.arrowUp);
    final offset = app.popular.scrollOffset;
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectVisibleFocus(tester, 12);
    expect(app.popular.scrollOffset, closeTo(offset, 0.5));
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    _expectVisibleFocus(tester, 11);
    expect(app.popular.scrollOffset, closeTo(offset, 0.5));
  });

  testWidgets('10ms DOWN then UP cancels old motion and returns to first row',
      (tester) async {
    final app = await mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 10));
    await _press(tester, LogicalKeyboardKey.arrowUp);
    _expectVisibleFocus(tester, 1);
    expect(app.popular.scrollOffset, lessThan(10));
    await tester.pump(const Duration(seconds: 1));
    _expectVisibleFocus(tester, 1);
  });

  testWidgets('held DOWN accumulates pending rows; latest RIGHT wins',
      (tester) async {
    await mount(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 10));
    for (var i = 0; i < 8; i++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectVisibleFocus(tester, 47);
    await tester.pump(const Duration(seconds: 1));
    _expectVisibleFocus(tester, 47);
  });

  testWidgets('leaving pending scroll for rail cancels it and restores content',
      (tester) async {
    final app = await mount(tester);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 10));
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(
        FocusManager.instance.primaryFocus!.ancestors
            .any((n) => n.debugLabel == 'TV navigation rail'),
        isTrue);
    final offset = app.popular.scrollOffset;
    await tester.pump(const Duration(seconds: 1));
    expect(app.popular.scrollOffset, closeTo(offset, 0.5));
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(FocusManager.instance.primaryFocus!.debugLabel, 'TV category 热门番组');
    expect(app.popular.scrollOffset, closeTo(offset, 0.5));
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectVisibleFocus(tester, 6);
  });

  testWidgets(
      'OK during scroll keeps detail focus, native return restores card',
      (tester) async {
    await mount(tester);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 10));
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('详情路由：本地测试'), findsOneWidget);
    final detailFocus = FocusManager.instance.primaryFocus;
    await tester.pump(const Duration(seconds: 1));
    expect(FocusManager.instance.primaryFocus, same(detailFocus));
    await rootNavigatorKey.currentState!.maybePop();
    await tester.pumpAndSettle();
    _expectVisibleFocus(tester, 6);
  });

  testWidgets('numeric preview supersedes pending directional scroll',
      (tester) async {
    await mount(tester);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 10));
    tvChannelInputController.addDigit(2);
    await tester.pumpAndSettle();
    _expectVisibleFocus(tester, 2);
    tvChannelInputController.cancel();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    _expectVisibleFocus(tester, 2);
  });

  testWidgets('ragged final row stops and retains category/function exits',
      (tester) async {
    final app = await mount(tester, count: 26);
    for (var i = 0; i < 4; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    _expectVisibleFocus(tester, 21);
    for (var i = 0; i < 4; i++) {
      await _press(tester, LogicalKeyboardKey.arrowRight);
    }
    _expectVisibleFocus(tester, 25);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectVisibleFocus(tester, 26);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectVisibleFocus(tester, 26);
    final queries = app.popular.queries;
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectVisibleFocus(tester, 26);
    expect(app.popular.queries, queries + 1,
        reason: 'DOWN at the loaded boundary requests the next batch once');
    for (final number in [21, 16, 11, 6, 1]) {
      await _press(tester, LogicalKeyboardKey.arrowUp);
      _expectVisibleFocus(tester, number);
    }
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(FocusManager.instance.primaryFocus!.debugLabel, 'TV category 热门番组');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectVisibleFocus(tester, 1);
    // This fixture returns no new items on pagination, just as the API's
    // current catch-and-return-empty path does on a failed request.
    expect(app.popular.queries, greaterThan(0));
    expect(app.popular.trendList.length, 26);
    expect(app.popular.isTimeOut, isFalse);
  });

  testWidgets('long directory stops at end and returns through recycled rows',
      (tester) async {
    final app = await mount(tester);
    for (var row = 1; row <= 23; row++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    _expectVisibleFocus(tester, 116);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectVisibleFocus(tester, 116);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectVisibleFocus(tester, 117);
    await tester.pump(const Duration(seconds: 1));
    _expectVisibleFocus(tester, 117);
    for (var row = 22; row >= 0; row--) {
      await _press(tester, LogicalKeyboardKey.arrowUp);
      _expectVisibleFocus(tester, row * 5 + 2);
    }
    expect(app.popular.scrollOffset, lessThan(10));
  });

  testWidgets('TV directory appends a batch without taking newer focus',
      (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Hive writes use real filesystem completion, outside the widget clock.
    await tester.runAsync(
        () => GStorage.putSetting(SettingsKeys.enableBangumiProxy, true));
    final controller = TvPopularController();
    final offsets = <int>[];
    final appendStarted = Completer<void>();
    VoidCallback? finishAppend;
    DioFactory.apiDio.interceptors.insert(0, InterceptorsWrapper(
      onRequest: (options, handler) {
        final offset = int.parse(options.uri.queryParameters['offset']!);
        offsets.add(offset);
        void respond(int first, int count) => handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {'data': _subjects(first, count)}));
        if (offset == 0) {
          respond(1, 24);
        } else {
          expect(offset, 24);
          expect(finishAppend, isNull,
              reason: 'A pending append must not request another batch');
          finishAppend = () => respond(25, 6);
          appendStarted.complete();
        }
      },
    ));
    await tester.runAsync(() =>
        controller.queryBangumiByTrend().timeout(const Duration(seconds: 5)));
    await tester.pumpWidget(MaterialApp(
        home: TvAppShell(child: PopularPage(controller: controller))));
    await tester.pumpAndSettle();
    tester.widget<BangumiCardV>(_poster(1)).focusNode!.requestFocus();
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectVisibleFocus(tester, 6);

    // Reach the loaded boundary and request its next row. The larger cards
    // need not cross the pixel prefetch threshold before this explicit DOWN.
    // Keep the append pending while newer directional input owns the focus.
    Future<void> moveWhileLoading(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      // Build the first animation frame before advancing its elapsed time.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
    }

    await moveWhileLoading(LogicalKeyboardKey.arrowDown);
    _expectVisibleFocus(tester, 11);
    await moveWhileLoading(LogicalKeyboardKey.arrowDown);
    _expectVisibleFocus(tester, 16);
    await moveWhileLoading(LogicalKeyboardKey.arrowDown);
    _expectVisibleFocus(tester, 21);
    await moveWhileLoading(LogicalKeyboardKey.arrowDown);
    _expectVisibleFocus(tester, 21);
    expect(appendStarted.isCompleted, isTrue);
    expect(controller.isLoadingMore, isTrue);
    await moveWhileLoading(LogicalKeyboardKey.arrowDown);
    _expectVisibleFocus(tester, 21);
    await moveWhileLoading(LogicalKeyboardKey.arrowRight);
    _expectVisibleFocus(tester, 22);
    expect(controller.trendList.length, 24);
    expect(offsets, [0, 24]);
    finishAppend!();
    await tester.pumpAndSettle();
    _expectVisibleFocus(tester, 22);
    expect(controller.trendList.length, 30);
    expect(controller.canLoadMore, isFalse);
    expect(controller.canRetryLoad, isFalse,
        reason: 'A successful nonempty short tail is a completed directory');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectVisibleFocus(tester, 27);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectVisibleFocus(tester, 27);
    expect(offsets, [0, 24],
        reason: 'The short tail stops automatic and boundary requests');
    expect(controller.isTimeOut, isFalse);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('empty append is reachable by DOWN and retries the same cursor',
      (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(
        () => GStorage.putSetting(SettingsKeys.enableBangumiProxy, true));
    final controller = TvPopularController();
    final offsets = <int>[];
    var appendAttempts = 0;
    FocusNode? focusAtRetry;
    DioFactory.apiDio.interceptors.insert(0, InterceptorsWrapper(
      onRequest: (options, handler) {
        final offset = int.parse(options.uri.queryParameters['offset']!);
        offsets.add(offset);
        final subjects = offset == 0
            ? _subjects(1, 24)
            : ++appendAttempts == 1
                ? <Map<String, Object>>[]
                : _subjects(25, 6);
        if (appendAttempts == 2) {
          focusAtRetry = FocusManager.instance.primaryFocus;
        }
        handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {'data': subjects}));
      },
    ));
    await tester.runAsync(() =>
        controller.queryBangumiByTrend().timeout(const Duration(seconds: 5)));
    await tester.pumpWidget(MaterialApp(
        home: TvAppShell(child: PopularPage(controller: controller))));
    await tester.pumpAndSettle();
    tester.widget<BangumiCardV>(_poster(1)).focusNode!.requestFocus();
    await tester.pumpAndSettle();
    for (final number in [6, 11, 16, 21]) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
      _expectVisibleFocus(tester, number);
    }
    expect(offsets, [0, 24]);
    expect(controller.trendList.length, 24);
    expect(controller.canLoadMore, isFalse);
    expect(controller.canRetryLoad, isTrue);
    final card = tester.widget<BangumiCardV>(_poster(21)).focusNode!;
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(
        FocusManager.instance.primaryFocus!.debugLabel, 'TV directory retry');
    final retry = find.byWidgetPredicate((widget) =>
        widget is TvFocusableSurface &&
        widget.focusNode?.debugLabel == 'TV directory retry');
    final footer = tester.getRect(retry);
    final viewport = tester.getRect(find.byType(CustomScrollView));
    expect(footer.top, greaterThanOrEqualTo(viewport.top));
    expect(footer.bottom, lessThanOrEqualTo(viewport.bottom + .5));
    await _press(tester, LogicalKeyboardKey.arrowUp);
    _expectVisibleFocus(tester, 21);
    expect(offsets, [0, 24]);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(
        FocusManager.instance.primaryFocus!.debugLabel, 'TV directory retry');
    await _press(tester, LogicalKeyboardKey.select);
    expect(focusAtRetry, same(card),
        reason: 'Retry focuses the existing card before removing its button');
    _expectVisibleFocus(tester, 21);
    expect(offsets, [0, 24, 24]);
    expect(controller.trendList.take(24).map((item) => item.id),
        List.generate(24, (index) => index + 1));
    expect(controller.trendList.length, 30);
    expect(controller.canRetryLoad, isFalse);
    expect(controller.isTimeOut, isFalse);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectVisibleFocus(tester, 26);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _expectVisibleFocus(tester, 26);
    expect(offsets, [0, 24, 24]);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
