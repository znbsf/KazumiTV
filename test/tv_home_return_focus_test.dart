import 'dart:io';
import 'dart:async';

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
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/services/player/history_playback_service.dart';
import 'package:kazumi/services/platform/app_remote.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
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
  setUp(() async {
    await GStorage.histories.clear();
    TvMode.setEnabledForTesting(true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.predidit.kazumi/tv_navigation'),
            (_) async => null);
  });
  tearDown(() => TvMode.setEnabledForTesting(false));

  Future<void> seed(WidgetTester tester) async {
    final old = History(
        focusItem(3), 1, 'old source', DateTime(2026, 10, 1), '/old', '1');
    final recent = History(focusItem(3), 7, 'recent source',
        DateTime(2026, 10, 2), '/recent', '7');
    recent.progresses[7] = Progress(7, 0, 42000);
    await tester.runAsync(
        () => GStorage.histories.putAll({old.key: old, recent.key: recent}));
  }

  testWidgets(
      'number timeout resumes latest history and returns to the same poster',
      (tester) async {
    await seed(tester);
    final app = await _mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(app.openedInfoIds, isEmpty);
    expect(app.playback.opened, hasLength(1));
    expect(app.playback.opened.single.adapterName, 'recent source');
    expect(app.playback.opened.single.lastWatchEpisode, 7);
    expect(app.playback.opened.single.progresses[7]!.progress.inSeconds, 42);
    expect(find.text('续播路由：仅验证参数，不是真实视频'), findsOneWidget);
    await _back(tester);
    expect(_focus(tester, 3).hasPrimaryFocus, true);
    await _open(tester, 3);
    expect(app.openedInfoIds, [3],
        reason: 'ordinary poster activation still opens details');
    expect(app.playback.opened, hasLength(1));
  });

  for (final key in [
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
  ]) {
    testWidgets('confirmation ${key.keyLabel} opens details after digits',
        (tester) async {
      await seed(tester);
      final app = await _mount(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(app.openedInfoIds, [3]);
      expect(app.playback.opened, isEmpty);
      await _back(tester);
      expect(_focus(tester, 3).hasPrimaryFocus, true);
    });
  }

  testWidgets('phone confirmation opens details after a number',
      (tester) async {
    await seed(tester);
    final app = await _mount(tester);
    final remote = AppRemote.instance;
    final shell = remote.attachShell();
    addTearDown(shell.release);
    expect(
        await remote.dispatch('digit3',
            revision: remote.state['revision'] as int),
        true);
    await tester.pumpAndSettle();
    expect(
        await remote.dispatch('ok', revision: remote.state['revision'] as int),
        true);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(app.openedInfoIds, [3]);
    expect(app.playback.opened, isEmpty);
  });

  testWidgets(
      'phone number timeout resumes history; unwatched numbers open details',
      (tester) async {
    await seed(tester);
    final app = await _mount(tester);
    final remote = AppRemote.instance;
    final shell = remote.attachShell();
    addTearDown(shell.release);
    expect(
        await remote.dispatch('digit3',
            revision: remote.state['revision'] as int),
        true);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(app.playback.opened, hasLength(1));
    expect(app.openedInfoIds, isEmpty);
    await _back(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(app.openedInfoIds, [4]);
    expect(app.playback.opened, hasLength(1));
  });

  testWidgets('unavailable history falls back to details', (tester) async {
    await seed(tester);
    final app = await _mount(tester);
    app.playback.resolve =
        (_, __) async => const HistoryPlaybackUnavailable('missing');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(app.openedInfoIds, [3]);
    expect(find.text('续播路由：仅验证参数，不是真实视频'), findsNothing);
  });

  testWidgets(
      'cancelled number resume never opens a late result or detail fallback',
      (tester) async {
    await seed(tester);
    final app = await _mount(tester);
    final pending = Completer<HistoryPlaybackResult>();
    RuleCancelToken? token;
    app.playback.resolve = (_, cancel) {
      token = cancel;
      return pending.future;
    };
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 400));
    expect(app.playback.opened, hasLength(1));
    await rootNavigatorKey.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(token!.isCancelled, true);
    pending.complete(HistoryPlaybackReady(OfflineVideoPlaybackArgs(
        bangumiItem: focusItem(3),
        pluginName: 'recent source',
        episodeNumber: 7,
        road: 0,
        downloadedEpisodes: [])));
    await tester.pumpAndSettle();
    expect(app.openedInfoIds, isEmpty);
    expect(find.byType(PopularPage), findsOneWidget);
    expect(_focus(tester, 3).hasPrimaryFocus, true);
  });

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
    final firstTop = tester.getTopLeft(_card(1)).dy;
    final stride = tester.getTopLeft(_card(6)).dy - firstTop;
    final header = tester.getRect(find.descendant(
        of: find.byType(PopularPage), matching: find.byType(AppBar)));
    _scroll(tester).jumpTo(firstTop + stride * 3 - header.bottom + 30);
    await tester.pumpAndSettle();
    // Row four is fully visible; row three is partially hidden by the fixed
    // category toolbar. Focus and the first visible poster have distinct ids.
    _focus(tester, 21).requestFocus();
    await tester.pumpAndSettle();
    final anchorTop = tester.getTopLeft(_card(16)).dy;
    await _open(tester, 21);
    app.popular.trendList
        .insertAll(0, List.generate(5, (i) => focusItem(101 + i)));
    await tester.pumpAndSettle();
    await _back(tester);
    expect(_focus(tester, 21).hasPrimaryFocus, isTrue);
    expect(tester.getTopLeft(_card(16)).dy, closeTo(anchorTop, 1));
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
    final card = tester.getRect(_card(3));
    final viewport = tester.getRect(_view);
    final header = tester.getRect(find.descendant(
        of: find.byType(PopularPage), matching: find.byType(AppBar)));
    expect(card.top, greaterThanOrEqualTo(header.bottom - .5));
    expect(card.bottom, lessThanOrEqualTo(viewport.bottom + .5));
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
