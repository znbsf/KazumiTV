import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/bean/widget/tv_artwork.dart';
import 'package:kazumi/bean/widget/tv_desktop_navigation.dart';
import 'package:kazumi/bean/widget/tv_focusable_surface.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/popular/popular_page.dart';
import 'package:kazumi/pages/popular/tv_recent_watch.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/platform/tv_channel_input.dart';
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

Finder _surface(String label) => find.byWidgetPredicate(
      (widget) =>
          widget is TvFocusableSurface && widget.focusNode?.debugLabel == label,
    );

FocusNode _node(WidgetTester tester, String label) =>
    tester.widget<TvFocusableSurface>(_surface(label)).focusNode!;

Finder _poster(int number) => find.byWidgetPredicate(
      (widget) => widget is BangumiCardV && widget.channelNumber == number,
    );

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

Future<FocusFixtureApp> _mount(
  WidgetTester tester, {
  double textScale = 1,
  Size viewport = const Size(1280, 720),
  Widget Function(FocusPopularController)? popularBuilder,
  bool startupRedirect = false,
  PageTransition? shellTransition,
  void Function(FocusFixtureApp)? configure,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final app = FocusFixtureApp(
      count: 120,
      textScale: textScale,
      popularBuilder: popularBuilder,
      initialRoute: startupRedirect ? '/' : '/tab/popular/',
      startupRedirect: startupRedirect,
      shellTransition: shellTransition);
  configure?.call(app);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  return app;
}

Widget _delayedPopular(
        ValueNotifier<bool> ready, FocusPopularController controller) =>
    ValueListenableBuilder<bool>(
      valueListenable: ready,
      builder: (context, mounted, _) {
        if (mounted) return PopularPage(controller: controller);
        // Keep the actual shell functions usable while its routed home has
        // not installed its category header, as in the cold APK startup.
        final navigation = TvDesktopNavigation.maybeOf(context)!;
        return Scaffold(
          body: Column(children: [
            SizedBox(
              height: 64,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: navigation.functionBar(context),
              ),
            ),
            const Expanded(child: Center(child: Text('Home awaiting mount'))),
          ]),
        );
      },
    );

Future<void> _seedRecent(
  WidgetTester tester, {
  List<int> ids = const [41, 42],
  DateTime? latest,
}) async {
  final time = latest ?? DateTime(2026, 10, 1, 16);
  final entries = [
    for (var index = 0; index < ids.length; index++)
      History(focusItem(ids[index]), 1, 'offline',
          time.subtract(Duration(seconds: index)), '', 'episode 1'),
  ];
  await tester.runAsync(() => GStorage.histories
      .putAll({for (final entry in entries) entry.key: entry}));
}

Future<void> _openRecentLink(WidgetTester tester, int id) async {
  _node(tester, 'TV recent $id').requestFocus();
  await tester.pumpAndSettle();
  await _press(tester, LogicalKeyboardKey.select);
}

List<String> _historySnapshot() => HistoryRepository()
    .getAllHistories()
    .map((history) => '${history.key}|${history.lastWatchEpisode}|'
        '${history.lastWatchEpisodeName}|'
        '${history.lastWatchTime.millisecondsSinceEpoch}')
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late PathProviderPlatform originalPaths;

  setUpAll(() async {
    originalPaths = PathProviderPlatform.instance;
    temporary = await Directory.systemTemp.createTemp('kazumi_home_desktop_');
    PathProviderPlatform.instance = _Paths(temporary.path);
    Hive.init(temporary.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    await temporary.delete(recursive: true);
  });
  setUp(() async {
    TvMode.setEnabledForTesting(true);
    tvArtworkController.select(null);
    await GStorage.histories.clear();
    await GStorage.putSetting(SettingsKeys.oledEnhance, false);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.predidit.kazumi/tv_navigation'),
      (_) async => null,
    );
  });
  tearDown(() {
    tvChannelInputController.cancel();
    tvArtworkController.select(null);
    TvMode.setEnabledForTesting(false);
  });

  testWidgets('home starts on Hot with one navigation row and six posters', (
    tester,
  ) async {
    await _mount(tester);
    final hot = tester.getRect(_surface('TV category 热门番组'));
    expect(_node(tester, 'TV category 热门番组').hasPrimaryFocus, isTrue);
    expect(find.byType(NavigationRail), findsNothing);
    for (final label in [
      'TV function 4',
      'TV search entry',
      'TV function 2',
      'TV function 1',
      'TV function 3',
    ]) {
      final rect = tester.getRect(_surface(label));
      expect(rect.center.dy, closeTo(hot.center.dy, 2));
      expect(rect.right, lessThanOrEqualTo(hot.left));
    }

    final first = tester.getRect(_poster(1));
    for (var number = 2; number <= 6; number++) {
      final rect = tester.getRect(_poster(number));
      expect(rect.top, closeTo(first.top, .1));
      expect(rect.left, greaterThan(first.left));
    }
    expect(tester.getRect(_poster(7)).top, greaterThan(first.bottom));
    final title = find.descendant(
      of: _poster(1),
      matching: find.text('本地测试番剧 1'),
    );
    expect(first.contains(tester.getCenter(title)), isTrue,
        reason: 'the title stays inside its poster instead of adding a row');
    expect(find.text('最近观看'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cross-group keys focus categories without changing the catalog',
      (
    tester,
  ) async {
    final app = await _mount(tester);
    final queries = app.popular.queries;
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_node(tester, 'TV function 3').hasPrimaryFocus, isTrue);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_node(tester, 'TV category 热门番组').hasPrimaryFocus, isTrue);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_node(tester, 'TV category 日常').hasPrimaryFocus, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(app.popular.currentTag, isEmpty);
    expect(app.popular.queries, queries,
        reason: 'passing or dwelling on a category must not select it');
    await _press(tester, LogicalKeyboardKey.select);
    expect(app.popular.currentTag, '日常');
    expect(app.popular.queries, queries + 1);
    expect(_node(tester, 'TV category 日常').hasPrimaryFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late mounted home completes startup Search to Hot handoff',
      (tester) async {
    final ready = ValueNotifier(false);
    addTearDown(ready.dispose);
    await _mount(tester,
        popularBuilder: (controller) => _delayedPopular(ready, controller));
    expect(_node(tester, 'TV search entry').hasPrimaryFocus, isTrue);
    expect(_surface('TV category 热门番组'), findsNothing);
    // The home arrives well after the former fixed two-frame repair window.
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    ready.value = true;
    await tester.pumpAndSettle();
    expect(_node(tester, 'TV category 热门番组').hasPrimaryFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new Search key cancels delayed automatic Hot focus',
      (tester) async {
    final ready = ValueNotifier(false);
    addTearDown(ready.dispose);
    await _mount(tester,
        popularBuilder: (controller) => _delayedPopular(ready, controller));
    expect(_node(tester, 'TV search entry').hasPrimaryFocus, isTrue);
    await _press(tester, LogicalKeyboardKey.keyA);
    expect(_node(tester, 'TV search entry').hasPrimaryFocus, isTrue,
        reason: 'new input owns Search without activating another destination');
    ready.value = true;
    await tester.pumpAndSettle();
    expect(_node(tester, 'TV search entry').hasPrimaryFocus, isTrue);
    expect(_node(tester, 'TV category 热门番组').hasPrimaryFocus, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late home readiness leaves a real function control focused',
      (tester) async {
    final ready = ValueNotifier(false);
    addTearDown(ready.dispose);
    await _mount(tester,
        popularBuilder: (controller) => _delayedPopular(ready, controller));
    final favorite = _node(tester, 'TV function 3');
    favorite.requestFocus();
    await tester.pumpAndSettle();
    ready.value = true;
    await tester.pumpAndSettle();
    expect(favorite.hasPrimaryFocus, isTrue,
        reason: 'readiness repairs only the startup Search or empty scope');
    expect(_node(tester, 'TV category 热门番组').hasPrimaryFocus, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('synthetic startup key does not cancel the pending Hot handoff',
      (tester) async {
    final ready = ValueNotifier(false);
    addTearDown(ready.dispose);
    await _mount(tester,
        popularBuilder: (controller) => _delayedPopular(ready, controller));
    final handler = ServicesBinding.instance.keyEventManager.keyMessageHandler!;
    handler(const KeyMessage([
      KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.capsLock,
          logicalKey: LogicalKeyboardKey.capsLock,
          timeStamp: Duration.zero,
          synthesized: true),
      KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.capsLock,
          logicalKey: LogicalKeyboardKey.capsLock,
          timeStamp: Duration.zero,
          synthesized: true),
    ], null));
    await tester.pumpAndSettle();
    expect(_node(tester, 'TV search entry').hasPrimaryFocus, isTrue);
    ready.value = true;
    await tester.pumpAndSettle();
    expect(_node(tester, 'TV category 热门番组').hasPrimaryFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Init navigate into the real tab fade keeps Hot as startup focus',
      (tester) async {
    await _mount(tester,
        startupRedirect: true,
        shellTransition: CustomTransition(
          duration: const Duration(milliseconds: 70),
          transitionsBuilder: (context, animation, secondary, child) =>
              FadeTransition(opacity: animation, child: child),
        ));
    expect(_node(tester, 'TV category 热门番组').hasPrimaryFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home navigation and recent return survive stripped debug labels',
      (tester) async {
    await _seedRecent(tester);
    await _mount(tester);
    final hot = _node(tester, 'TV category 热门番组');
    final favorite = _node(tester, 'TV function 3');
    final recent = _node(tester, 'TV recent 41');
    for (final node in FocusManager.instance.rootScope.descendants.toList()) {
      node.debugLabel = null;
    }
    expect(hot.debugLabel, isNull);
    expect(recent.debugLabel, isNull);
    expect(TvDesktopNavigation.homeFocusOf(hot)?.category, '');
    favorite.requestFocus();
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(hot.hasPrimaryFocus, isTrue,
        reason: 'Favorite Right uses the runtime Hot identity in release');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(recent.hasPrimaryFocus, isTrue,
        reason: 'category Down uses the recent kind, not its stripped label');
    favorite.requestFocus();
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(recent.hasPrimaryFocus, isTrue,
        reason: 'function Down uses the same release-safe recent identity');
    await _press(tester, LogicalKeyboardKey.select);
    await rootNavigatorKey.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(recent.hasPrimaryFocus, isTrue,
        reason:
            'detail return matches the recent subject via runtime identity');
    expect(tester.takeException(), isNull);
  });

  testWidgets('home ready waits for same-frame Search focus request to apply',
      (tester) async {
    final ready = ValueNotifier(false);
    addTearDown(ready.dispose);
    await _mount(tester,
        popularBuilder: (controller) => _delayedPopular(ready, controller));
    final search = _node(tester, 'TV search entry');
    var sawOuterScopeWithPendingSearch = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Reproduce the ordinary APK trace: before the ready callback, Search
      // has requested focus but the primary node is still the outer scope.
      FocusManager.instance.rootScope.requestScopeFocus();
      FocusManager.instance.applyFocusChangesIfNeeded();
      search.requestFocus();
      sawOuterScopeWithPendingSearch =
          FocusManager.instance.primaryFocus == FocusManager.instance.rootScope;
    });
    ready.value = true;
    await tester.pumpAndSettle();
    expect(sawOuterScopeWithPendingSearch, isTrue);
    expect(_node(tester, 'TV category 热门番组').hasPrimaryFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 1.25]) {
    testWidgets(
        'short and long focus summaries keep poster positions at $scale', (
      tester,
    ) async {
      final longSummary = List.filled(60, '较长的离线简介用于验证两行省略和海报位置。').join();
      await _mount(tester, textScale: scale, configure: (app) {
        app.popular.trendList[0].summary = '简短简介。';
        app.popular.trendList[1].summary = longSummary;
      });
      tester.widget<BangumiCardV>(_poster(1)).focusNode!.requestFocus();
      await tester.pumpAndSettle();
      final before = tester.getRect(_poster(3));
      final spotlight = find.byKey(const Key('tv-home-spotlight'));
      expect(tester.getSize(spotlight).height, closeTo(74 * scale, .1));
      expect(find.text('简短简介。'), findsOneWidget);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(find.text(longSummary), findsOneWidget);
      expect(tester.getRect(_poster(3)), before,
          reason: 'text length must not shift a neighboring poster');
      expect(tester.getSize(spotlight).height, closeTo(74 * scale, .1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'recent links read Dart history, deduplicate, and open only details', (
    tester,
  ) async {
    final entries = [
      History(focusItem(41), 12, '来源 A', DateTime(2026, 10, 1, 14), '', '第12集'),
      History(focusItem(41), 11, '来源 B', DateTime(2026, 10, 1, 13), '', '第11集'),
      History(focusItem(42), 3, '来源 C', DateTime(2026, 10, 1, 12), '', '第3集'),
      History(focusItem(43), 5, '来源 D', DateTime(2026, 10, 1, 11), '', '第5集'),
    ];
    await tester.runAsync(() async {
      await GStorage.histories
          .putAll({for (final entry in entries) entry.key: entry});
    });
    final before = _historySnapshot();
    final app = await _mount(tester);
    expect(
        TvRecentWatch.items().map((entry) => entry.bangumiItem.id), [41, 42]);
    expect(find.text('本地测试番剧 41 · 第12集'), findsOneWidget);
    expect(find.text('本地测试番剧 41 · 第11集'), findsNothing);
    expect(find.text('本地测试番剧 43 · 第5集'), findsNothing);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_node(tester, 'TV recent 41').hasPrimaryFocus, isTrue,
        reason: 'category Down reaches the separate recent row first');
    _node(tester, 'TV function 3').requestFocus();
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_node(tester, 'TV recent 41').hasPrimaryFocus, isTrue,
        reason: 'function Down also reaches recent links before posters');
    final scroll = tester
        .widget<CustomScrollView>(
          find.byType(CustomScrollView),
        )
        .controller!;
    scroll.jumpTo(600);
    await tester.pumpAndSettle();
    final recentRect = tester.getRect(_surface('TV recent 41'));
    final hotRect = tester.getRect(_surface('TV category 热门番组'));
    expect(recentRect.top, greaterThanOrEqualTo(hotRect.bottom));
    expect(recentRect.bottom, lessThan(tester.view.physicalSize.height));
    expect(_surface('TV recent 41').hitTestable(), findsOneWidget,
        reason: 'recent links remain usable after the spotlight scrolls away');
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    _node(tester, 'TV recent 41').requestFocus();
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('详情路由：本地测试'), findsOneWidget);
    expect(app.openedInfoIds, [41]);
    expect(app.playback.opened, isEmpty);
    expect(_historySnapshot(), before,
        reason: 'browsing a recent link must not write playback progress');
    await rootNavigatorKey.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(_node(tester, 'TV recent 41').hasPrimaryFocus, isTrue);

    final updated = History(
      focusItem(41),
      13,
      '来源 A',
      DateTime(2026, 10, 1, 15),
      '',
      '第13集',
    );
    await tester.runAsync(() => GStorage.histories.put(updated.key, updated));
    await tester.pumpAndSettle();
    expect(find.text('本地测试番剧 41 · 第13集'), findsOneWidget);
    expect(find.text('本地测试番剧 41 · 第12集'), findsNothing);
    expect(app.playback.opened, isEmpty);
    await tester.runAsync(() => GStorage.histories.clear());
    await tester.pumpAndSettle();
    expect(find.text('最近观看'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recent detail return yields to a new category selection',
      (tester) async {
    await _seedRecent(tester);
    final app = await _mount(tester);
    final category = tester.widget<TvFocusableSurface>(
      _surface('TV category 日常'),
    );
    await _openRecentLink(tester, 41);
    await rootNavigatorKey.currentState!.maybePop();
    // Deliver the new command before the old return's endOfFrame completes.
    category.onPressed();
    category.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    expect(app.popular.currentTag, '日常');
    expect(category.focusNode!.hasPrimaryFocus, isTrue);
    expect(_node(tester, 'TV recent 41').hasPrimaryFocus, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recent detail return yields to a new number preview',
      (tester) async {
    await _seedRecent(tester);
    final app = await _mount(tester);
    final hot = _node(tester, 'TV category 热门番组');
    final recent = _node(tester, 'TV recent 41');
    await _openRecentLink(tester, 41);
    await rootNavigatorKey.currentState!.maybePop();
    hot.requestFocus();
    // The actual shell-to-home number event starts a preview without waiting
    // for the previous detail return or its frame to settle.
    tvChannelInputController.addDigit(2);
    await tester.pump();
    await tester.pump();
    expect(recent.hasPrimaryFocus, isFalse,
        reason:
            'a stale recent return cannot take focus during number preview');
    await tester.pumpAndSettle();
    expect(tester.widget<BangumiCardV>(_poster(2)).focusNode!.hasPrimaryFocus,
        isTrue);
    expect(app.openedInfoIds, [41],
        reason: 'number preview has not reached its delayed detail commit');
    tvChannelInputController.cancel();
    expect(tester.takeException(), isNull);
  });

  testWidgets('recent detail return yields to a new recent direction key',
      (tester) async {
    await _seedRecent(tester);
    await _mount(tester);
    final first = _node(tester, 'TV recent 41');
    final second = _node(tester, 'TV recent 42');
    await _openRecentLink(tester, 41);
    await rootNavigatorKey.currentState!.maybePop();
    first.requestFocus();
    await tester.idle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.idle();
    expect(second.hasPrimaryFocus, isTrue,
        reason: 'the new direction command is delivered before return frame');
    await tester.pumpAndSettle();
    expect(second.hasPrimaryFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final height in [720.0, 480.0]) {
    testWidgets(
        'recent links reach navigation and visible grid at height $height',
        (tester) async {
      await _seedRecent(tester);
      await _mount(tester, viewport: Size(1280, height));
      for (final id in [41, 42]) {
        _node(tester, 'TV recent $id').requestFocus();
        await tester.pumpAndSettle();
        await _press(tester, LogicalKeyboardKey.arrowUp);
        final upper = FocusManager.instance.primaryFocus;
        expect(upper, isNot(isA<FocusScopeNode>()));
        expect(
          upper?.debugLabel?.startsWith('TV category ') == true ||
              upper?.debugLabel?.startsWith('TV function ') == true ||
              upper?.debugLabel == 'TV search entry',
          isTrue,
          reason: 'native recent Up uses geometry to the top navigation row',
        );
        expect(upper!.context?.mounted, isTrue);

        _node(tester, 'TV recent $id').requestFocus();
        await tester.pumpAndSettle();
        await _press(tester, LogicalKeyboardKey.arrowDown);
        final label = FocusManager.instance.primaryFocus?.debugLabel;
        expect(label, startsWith('TV channel '));
        final number = int.parse(label!.substring('TV channel '.length));
        expect(_poster(number).hitTestable(), findsOneWidget);
      }

      _node(tester, 'TV category 热门番组').requestFocus();
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      scroll.jumpTo(600);
      await tester.pumpAndSettle();
      _node(tester, 'TV recent 41').requestFocus();
      await tester.pumpAndSettle();
      expect(_surface('TV recent 41').hitTestable(), findsOneWidget);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      final label = FocusManager.instance.primaryFocus?.debugLabel;
      expect(label, startsWith('TV channel '));
      final number = int.parse(label!.substring('TV channel '.length));
      final poster = tester.getRect(_poster(number));
      final recent = tester.getRect(_surface('TV recent 41'));
      expect(poster.top, greaterThanOrEqualTo(recent.bottom - .5),
          reason: 'a realized poster must clear the pinned recent/navigation');
      expect(_poster(number).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('recent history replacement retains pending origin then frees it',
      (tester) async {
    await _seedRecent(tester);
    await _mount(tester);
    final old = _node(tester, 'TV recent 41');
    await _openRecentLink(tester, 41);
    await _seedRecent(tester, ids: [43, 44], latest: DateTime(2026, 10, 1, 17));
    await tester.pumpAndSettle();
    expect(_surface('TV recent 41'), findsNothing);
    void listener() {}
    expect(() => old.addListener(listener), returnsNormally,
        reason: 'the pending return owner can safely inspect its origin');
    old.removeListener(listener);
    await rootNavigatorKey.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(_node(tester, 'TV recent 43').hasPrimaryFocus, isTrue,
        reason: 'a deleted origin returns to the neighboring recent slot');
    expect(() => old.addListener(listener), throwsFlutterError,
        reason: 'obsolete nodes are disposed once their return use ends');
    expect(tester.takeException(), isNull);
  });
}
