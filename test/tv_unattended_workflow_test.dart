// Unattended Dart business/routing loop, not hardware E2E. Pages, controllers,
// Hive repositories, source rules, HTTP and dialogs are real. Only catalog API
// transport and the MPV/native media destination have explicit fixture bounds.
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/card/bangumi_history_card.dart';
import 'package:kazumi/bean/widget/tv_focusable_surface.dart';
import 'package:kazumi/modules/collect/collect_change_module.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/modules/search/search_history_module.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/collect/collect_page.dart';
import 'package:kazumi/pages/history/history_page.dart';
import 'package:kazumi/pages/info/info_page.dart';
import 'package:kazumi/pages/info/source_sheet.dart';
import 'package:kazumi/pages/search/search_page.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/repositories/search_history_repository.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:kazumi/services/player/episode_identity.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/async_session.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/unattended_flow_fixture.dart';

class _WorkflowPaths extends PathProviderPlatform {
  _WorkflowPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

// Bypass widget tests' synthetic HTTP-400 client only for this Dio adapter.
// The request interceptor below rejects every non-loopback destination.
class _LoopbackHttpClient extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}

class _ChapterServer {
  _ChapterServer(this.server) {
    server.listen(_serve);
  }

  final HttpServer server;
  final paths = <String>[];
  bool reorderPrimary = false;
  Completer<void> delayedReceived = Completer<void>();
  Completer<void> releaseDelayed = Completer<void>();
  String get baseUrl => 'http://127.0.0.1:${server.port}';

  Plugin plugin(String name) => Plugin.fromTemplate()
    ..name = name
    ..baseUrl = baseUrl
    ..searchURL = '$baseUrl/search?source=$name&q=@keyword'
    ..searchList = '//article'
    ..searchName = '//a'
    ..searchResult = '//a'
    ..chapterRoads = '//div[@class="road"]'
    ..chapterResult = '//a';

  String get secondaryHtml => '''
<html><body>
<div class="road"><a href="/alternate/2">EP2</a><a href="/alternate/1">第1集</a></div>
<div class="road"><a href="/ambiguous/1a">EP1</a><a href="/ambiguous/1b">第1話</a></div>
<div class="road"><a href="/special/1">OVA1</a><a href="/trailer/1">第1集预告</a></div>
</body></html>
''';

  Future<void> _serve(HttpRequest request) async {
    paths.add(request.uri.path);
    request.response.headers.contentType = ContentType.html;
    if (request.uri.path == '/search') {
      final source = request.uri.queryParameters['source'] == 'secondary'
          ? '/catalog-b'
          : '/catalog-a';
      request.response.write(
          '<html><article><a href="$source">Loopback chapter result</a></article></html>');
    } else if (request.uri.path == '/catalog-a') {
      final episodes = reorderPrimary
          ? '<a href="/primary/2">EP2</a><a href="/primary/1">EP1</a>'
          : '<a href="/primary/1">EP1</a><a href="/primary/2">EP2</a>';
      request.response.write('<html><div class="road">$episodes</div></html>');
    } else if (request.uri.path == '/catalog-b') {
      request.response.write(secondaryHtml);
    } else if (request.uri.path == '/slow') {
      if (!delayedReceived.isCompleted) delayedReceived.complete();
      await releaseDelayed.future;
      request.response.write(secondaryHtml);
    } else {
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  }
}

Map<String, dynamic> _subjectJson(int id) => {
      'id': id,
      'type': 2,
      'name': 'Workflow subject $id',
      'name_cn': 'Workflow subject $id',
      'summary': 'Deterministic business workflow metadata.',
      'date': '2026-09-06',
      'images': <String, String>{},
      'tags': <dynamic>[],
      'rating': {
        'rank': id,
        'score': 8.0,
        'total': 100,
        'count': List.filled(10, 10),
      },
    };

Finder _subjectSurface(int id) => find
    .ancestor(
      of: find.text('Workflow subject $id'),
      matching: find.byType(TvFocusableSurface),
    )
    .last;

FocusNode _subjectFocus(WidgetTester tester, int id) => Focus.of(
      tester.element(find
          .descendant(
            of: _subjectSurface(id),
            matching: find.byType(AnimatedScale),
          )
          .first),
    );

FocusNode _collectionSubjectFocus(WidgetTester tester, int id) => tester
    .widget<InkWell>(find.byWidgetPredicate((widget) =>
        widget is InkWell &&
        widget.focusNode?.debugLabel == 'TV collection $id'))
    .focusNode!;

Future<void> _pumpUntil(
    WidgetTester tester, bool Function() ready, String reason) async {
  for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
    // Hive and a real loopback socket need an actual event-loop turn, while
    // widget transitions still advance through the controlled test clock.
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(ready(), isTrue, reason: reason);
  await tester.pumpAndSettle();
}

Future<void> _backUntil(WidgetTester tester, Finder destination) async {
  for (var attempt = 0;
      attempt < 4 &&
          (destination.evaluate().isEmpty ||
              find.byType(SourceSheet).evaluate().isNotEmpty);
      attempt++) {
    await rootNavigatorKey.currentState!.maybePop();
    await tester.pumpAndSettle();
  }
  expect(destination, findsOneWidget);
  expect(find.byType(SourceSheet), findsNothing,
      reason:
          'A non-opaque source sheet can leave InfoPage onstage underneath');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporaryDirectory;
  late PathProviderPlatform previousPaths;
  late _ChapterServer sourceServer;
  late Zone persistenceZone;
  final searchOffsets = <int>[];

  setUpAll(() async {
    persistenceZone = Zone.current;
    temporaryDirectory =
        await Directory.systemTemp.createTemp('kazumi_unattended_flow_');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _WorkflowPaths(temporaryDirectory.path);
    Hive.init(temporaryDirectory.path);
    await GStorage.init();
    await GStorage.putSetting(SettingsKeys.bangumiSyncEnable, false);
    await GStorage.putSetting(SettingsKeys.webDavEnable, false);
    sourceServer =
        _ChapterServer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
  });

  setUp(() async {
    TvMode.setEnabledForTesting(true);
    await GStorage.histories.clear();
    await GStorage.collectibles.clear();
    await GStorage.collectChanges.clear();
    await GStorage.searchHistory.clear();
    searchOffsets.clear();
    sourceServer.paths.clear();
    sourceServer.reorderPrimary = false;
    sourceServer.delayedReceived = Completer<void>();
    sourceServer.releaseDelayed = Completer<void>();
    DioFactory.reset();
    DioFactory.apiDio.interceptors.insert(0,
        InterceptorsWrapper(onRequest: (options, handler) {
      final offset = int.tryParse(options.uri.queryParameters['offset'] ?? '');
      if (options.method != 'POST' || offset == null) {
        handler.reject(DioException(
            requestOptions: options,
            error: StateError('Unexpected live API request: ${options.uri}')));
        return;
      }
      searchOffsets.add(offset);
      final ids =
          offset == 0 ? List.generate(20, (index) => index + 1) : [20, 21, 22];
      handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: {'data': ids.map(_subjectJson).toList()}));
    }));
    DioFactory.pluginDio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => _LoopbackHttpClient().createHttpClient(null),
    );
    DioFactory.pluginDio.interceptors.insert(0,
        InterceptorsWrapper(onRequest: (options, handler) {
      if (options.uri.host != '127.0.0.1' ||
          options.uri.port != sourceServer.server.port) {
        handler.reject(DioException(
            requestOptions: options,
            error: StateError('Non-fixture source request: ${options.uri}')));
        return;
      }
      handler.next(options);
    }));
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.predidit.kazumi/tv_navigation'),
        (_) async => null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'), (_) async => null);
  });

  tearDown(() {
    TvMode.setEnabledForTesting(false);
    if (!sourceServer.releaseDelayed.isCompleted) {
      sourceServer.releaseDelayed.complete();
    }
    DioFactory.pluginDio.close(force: true);
    DioFactory.apiDio.close(force: true);
    DioFactory.reset();
  });
  tearDownAll(() async {
    DioFactory.reset();
    await sourceServer.server
        .close(force: true)
        .timeout(const Duration(seconds: 5));
    await Hive.close();
    PathProviderPlatform.instance = previousPaths;
    await temporaryDirectory.delete(recursive: true);
  });

  testWidgets(
      'real pages persist and restore a paged favorite/history workflow with explicit source transfer',
      (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final primary = sourceServer.plugin('primary');
    final app = UnattendedFlowApp(
        sourcePlugins: [primary], persistenceZone: persistenceZone);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('tv-search-editor')), 'loopback');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _pumpUntil(tester, () => app.search.bangumiList.length == 20,
        'SearchPage must submit through the real controller/API parser');
    expect(searchOffsets, [0]);
    await tester.drag(
        find.byType(CustomScrollView).first, const Offset(0, -2400));
    await _pumpUntil(tester, () => app.search.bangumiList.length == 22,
        'Scrolling must fetch offset 20 and deduplicate overlapping subject 20');
    expect(searchOffsets, [0, 20]);
    expect(app.search.hasMoreSearchResults, isFalse);
    expect(
        app.search.bangumiList.map((item) => item.id).toSet(), hasLength(22));

    await tester.scrollUntilVisible(_subjectSurface(21), 250,
        scrollable: find
            .descendant(
                of: find.byType(CustomScrollView).first,
                matching: find.byType(Scrollable))
            .first);
    _subjectFocus(tester, 21).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byType(InfoPage), findsOneWidget);
    expect(app.openedSubjectIds.last, 21);

    // The detail page's real remote action row opens its real collection menu.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await _pumpUntil(tester, () => app.collection.collectibles.length == 1,
        'CollectButton must run CollectController and the disk repository');
    expect(app.collection.collectibles.single.bangumiItem.id, 21);
    expect(app.collection.collectibles.single.type, 1);
    expect(GStorage.collectChanges.values.single.bangumiID, 21);

    final selectedSubject =
        app.search.bangumiList.firstWhere((item) => item.id == 21);
    // Results can reorder while detail is open; Back must follow the subject ID.
    app.search.bangumiList.remove(selectedSubject);
    app.search.bangumiList.insert(3, selectedSubject);
    await tester.tap(find.widgetWithText(FilledButton, '开始观看'));
    await _pumpUntil(
        tester,
        () => find.text('Loopback chapter result').evaluate().isNotEmpty,
        'SourceSheet must run a real RuleEngine search over loopback HTTP');
    await tester.tap(find.text('Loopback chapter result'));
    await _pumpUntil(
        tester,
        () => find.byType(StubNativeVideoBoundary).evaluate().isNotEmpty,
        'Parsed source chapters must reach the actual /video/ route arguments');
    expect(sourceServer.paths, containsAll(['/search', '/catalog-a']));
    expect(find.text('subject 21; episode 1; offset 0'), findsOneWidget);

    await tester.tap(find.byKey(const Key('workflow-unplayed-snapshot')));
    await tester.pump();
    expect(app.historyRepository.getAllHistories(), isEmpty,
        reason: 'A prepared route/seek offset is not watched history');
    await tester.tap(find.byKey(const Key('workflow-played-snapshot')));
    await _pumpUntil(tester, () => app.history.histories.length == 1,
        'Recorder must write actual played state through HistoryController');
    final savedHistory = app.history.histories.single;
    expect(savedHistory.bangumiItem.id, 21);
    expect(savedHistory.lastWatchEpisodeName, 'EP1');
    expect(savedHistory.episodePageUrl, '${sourceServer.baseUrl}/primary/1');
    expect(savedHistory.progresses[1]!.progress.inSeconds, 347);
    await _backUntil(tester, find.byType(InfoPage));
    await rootNavigatorKey.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsOneWidget);
    expect(_subjectFocus(tester, 21).hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(app.openedSubjectIds.last, 21);
    await rootNavigatorKey.currentState!.maybePop();
    await tester.pumpAndSettle();

    // Route through the real collection page, then return by the same subject ID.
    tester.element(find.byType(SearchPage)).pushNamed('/collection/');
    await tester.pumpAndSettle();
    expect(find.byType(CollectPage), findsOneWidget);
    _collectionSubjectFocus(tester, 21).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byType(InfoPage), findsOneWidget);
    await rootNavigatorKey.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(_collectionSubjectFocus(tester, 21).hasPrimaryFocus, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    // Close/reopen the real data files and discard their controller caches.
    // Settings remain open because GStorage's settings reference is late final;
    // this is a persisted-data restart, not a claim of process/native cold boot.
    await tester.runAsync(() async {
      debugPrint('WORKFLOW: closing persisted Hive boxes');
      await GStorage.histories.close();
      await GStorage.collectibles.close();
      await GStorage.searchHistory.close();
      await GStorage.collectChanges.close();
      GStorage.histories = await Hive.openBox<History>('histories');
      GStorage.collectibles =
          await Hive.openBox<CollectedBangumi>('collectibles');
      GStorage.searchHistory =
          await Hive.openBox<SearchHistory>('searchHistory');
      GStorage.collectChanges =
          await Hive.openBox<CollectedBangumiChange>('collectchanges');
      debugPrint('WORKFLOW: reopened persisted Hive boxes');
    });
    sourceServer.reorderPrimary = true;
    final restoredSubject = GStorage.histories.values.single.bangumiItem;
    final restored = UnattendedFlowApp(
        persistenceZone: persistenceZone,
        sourcePlugins: [primary],
        initialRoute: '/history/',
        sourceSubject: restoredSubject);
    await tester.pumpWidget(restored);
    await tester.pumpAndSettle();
    restored.collection.loadCollectibles();
    expect(restored.history.histories.single, isNot(same(savedHistory)));
    expect(restored.history.histories.single.bangumiItem.id, 21);
    expect(restored.collection.collectibles.single.type, 1);
    expect(
        SearchHistoryRepository().getAllHistories().single.keyword, 'loopback');
    expect(GStorage.collectChanges.values.single.action, 1);

    final historyCard =
        tester.widget<BangumiHistoryCardV>(find.byType(BangumiHistoryCardV));
    historyCard.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await _pumpUntil(
        tester,
        () => find.byType(StubNativeVideoBoundary).evaluate().isNotEmpty,
        'HistoryPage must resolve the real saved source after reopening Hive');
    expect(find.text('subject 21; episode 2; offset 347'), findsOneWidget,
        reason: 'EP1 moved to index 2; resume must follow its saved page URL');
    await rootNavigatorKey.currentState!.maybePop();
    await tester.pumpAndSettle();
    final returnedCard =
        tester.widget<BangumiHistoryCardV>(find.byType(BangumiHistoryCardV));
    expect(returnedCard.historyItem.key, savedHistory.key);
    expect(returnedCard.focusNode!.hasPrimaryFocus, isTrue);

    restored.plugins.pluginList.replaceRange(0,
        restored.plugins.pluginList.length, [sourceServer.plugin('secondary')]);
    tester.element(find.byType(HistoryPage)).pushNamed('/sources/');
    await _pumpUntil(
        tester,
        () => find.text('Loopback chapter result').evaluate().isNotEmpty,
        'The destination source must produce its own real search result');
    await tester.tap(find.text('Loopback chapter result'));
    await _pumpUntil(tester, () => find.text('同集换源').evaluate().isNotEmpty,
        'Cross-source transfer must wait for an explicit user choice');
    expect(restored.openedVideoArgs, hasLength(1),
        reason: 'Matching alone must not open a new player route');
    expect(find.textContaining('继续 347 秒'), findsOneWidget,
        reason: 'Ambiguous and special roads must not offer borrowed progress');
    await tester.tap(find.widgetWithText(TextButton, '手动选集'));
    await _pumpUntil(
        tester,
        () => find.byType(StubNativeVideoBoundary).evaluate().isNotEmpty,
        'Manual choice must reach a fresh /video/ route');
    expect(restored.openedVideoArgs.last.transfer, isNull);
    expect(restored.openedVideoArgs.last.allowHistoryResume, isFalse);
    expect(find.text('subject 21; episode 1; offset 0'), findsOneWidget);
    await rootNavigatorKey.currentState!.maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Loopback chapter result'));
    await _pumpUntil(tester, () => find.text('同集换源').evaluate().isNotEmpty,
        'Reopening a source must again require confirmation');
    await tester.tap(find.textContaining('继续 347 秒'));
    await _pumpUntil(
        tester,
        () => find.byType(StubNativeVideoBoundary).evaluate().isNotEmpty,
        'Confirmed unique episode must reach the destination route');
    final confirmed = restored.openedVideoArgs.last;
    expect(confirmed.transfer!.offset, 347);
    expect(confirmed.transfer!.episode, 2);
    expect(
        confirmed.transfer!.matches(
            currentBangumiId: 21,
            currentPlugin: 'secondary',
            currentSrc: confirmed.src,
            roads: confirmed.roads,
            baseUrl: confirmed.plugin.baseUrl),
        isTrue);
    expect(find.text('subject 21; episode 2; offset 347'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    // Close keep-alive loopback connections before widget timer invariants.
    DioFactory.pluginDio.close(force: true);
    DioFactory.apiDio.close(force: true);
    DioFactory.reset();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'real delayed chapter HTTP cannot apply an old identity/session offset',
      (tester) async {
    await tester.runAsync(() async {
      final cancelToken = RuleCancelToken();
      try {
        final secondary = sourceServer.plugin('secondary');
        final roads = await secondary
            .queryChapterRoads('/catalog-b', cancelToken: cancelToken)
            .timeout(const Duration(seconds: 5));
        expect(roads, hasLength(3));
        expect(roads.first.identifier, ['EP2', '第1集']);
        final owner = AsyncSessionOwner();
        final current = EpisodeIdentity(
            title: 'EP1', pageUrl: '${sourceServer.baseUrl}/primary/1');
        EpisodeTransferSelection? resolve(int road, AsyncSession session) =>
            resolveEpisodeTransfer(
                current: current,
                candidates: episodeIdentitiesForRoad(roads[road],
                    baseUrl: secondary.baseUrl),
                position: const Duration(seconds: 347),
                duration: const Duration(minutes: 24),
                session: session,
                acrossSources: true);
        final session = owner.begin();
        expect(resolve(0, session), (episodeIndex: 1, offset: 347));
        expect(resolve(1, session), isNull);
        expect(resolve(2, session), isNull);

        final pendingSession = owner.begin();
        final delayed =
            secondary.queryChapterRoads('/slow', cancelToken: cancelToken);
        await sourceServer.delayedReceived.future
            .timeout(const Duration(seconds: 5));
        owner.begin();
        sourceServer.releaseDelayed.complete();
        final lateRoads = await delayed.timeout(const Duration(seconds: 5));
        expect(
            resolveEpisodeTransfer(
                current: current,
                candidates: episodeIdentitiesForRoad(lateRoads.first,
                    baseUrl: secondary.baseUrl),
                position: const Duration(seconds: 347),
                duration: const Duration(minutes: 24),
                session: pendingSession,
                acrossSources: true),
            isNull);
        expect(sourceServer.paths, ['/catalog-b', '/slow']);
      } finally {
        if (!sourceServer.releaseDelayed.isCompleted) {
          sourceServer.releaseDelayed.complete();
        }
        cancelToken.cancel();
      }
    });
  });
}
