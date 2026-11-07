import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:kazumi/request/core/dio_factory.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/card/bangumi_info_card.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/widget/collect_button.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/bangumi_tag.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/pages/info/info_page.dart';
import 'package:kazumi/pages/info/tv_detail_actions.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

class _Collect implements CollectController {
  int updates = 0;
  @override
  Future<void> updateLocalCollect(BangumiItem item) async {
    updates++;
  }

  @override
  int getCollectType(BangumiItem item) => 0;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Info extends InfoController {
  _Info(super.collectController);
  final requests = <Completer<bool>>[];
  String? nextSummary;
  @override
  Future<bool> queryBangumiInfoByID(int id, {String type = 'init'}) async {
    isLoading = true;
    final response = Completer<bool>();
    requests.add(response);
    try {
      final result = await response.future;
      if (result && nextSummary != null) bangumiItem.summary = nextSummary!;
      return result;
    } finally {
      isLoading = false;
    }
  }
}

class _MetadataAdapter implements HttpClientAdapter {
  _MetadataAdapter(this.succeed);
  final bool succeed;
  int calls = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    calls++;
    return ResponseBody.fromString(
        jsonEncode({
          'id': 71,
          'type': 2,
          'name': 'Fetched title',
          'summary': '',
          'rating': {'rank': 0, 'score': 0, 'total': 0},
          'images': {'large': 'https://fixture.invalid/fetched.jpg'},
        }),
        succeed ? 200 : 503,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}

class _FailedCovers implements BaseCacheManager {
  int calls = 0;

  @override
  Stream<FileResponse> getFileStream(String url,
      {String? key, Map<String, String>? headers, bool withProgress = false}) {
    calls++;
    return Stream.error(const SocketException('cover fixture failure'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _flushCover(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
}

Future<void> _exhaustCovers(WidgetTester tester) async {
  await _flushCover(tester);
  for (var i = 0; i < 2; i++) {
    await tester.pump(const Duration(milliseconds: 3));
    await _flushCover(tester);
  }
}

FocusNode _coverRetry(WidgetTester tester) =>
    Focus.of(tester.element(find.text('重试封面')));

_FailedCovers _failCovers() {
  final previous = CachedNetworkImageProvider.defaultCacheManager;
  final cache = _FailedCovers();
  CachedNetworkImageProvider.defaultCacheManager = cache;
  NetworkImgLayer.tvCoverRetryDelaysForTesting = const [
    Duration(milliseconds: 1),
    Duration(milliseconds: 2),
  ];
  addTearDown(() {
    CachedNetworkImageProvider.defaultCacheManager = previous;
    NetworkImgLayer.tvCoverRetryDelaysForTesting = null;
    NetworkImgLayer.clearTvCoverMemory();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  return cache;
}

BangumiItem _subject({String summary = ''}) => BangumiItem(
      id: 71,
      type: 2,
      name: 'Metadata fixture',
      nameCn: '',
      summary: summary,
      airDate: '',
      airWeekday: 1,
      rank: 0,
      images: {},
      tags: [],
      alias: [],
      ratingScore: 0,
      votes: 0,
      votesCount: List.filled(10, 0),
      info: '',
    );

Future<_Info> _open(WidgetTester tester,
    {String summary = '',
    bool tv = true,
    BangumiItem? item,
    ThemeData? theme,
    Size size = const Size(1280, 720),
    GlobalKey<NavigatorState>? navigator}) async {
  TvMode.setEnabledForTesting(tv);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final collect = _Collect();
  bootstrapModule(createModule(register: (c) {
    c.addInstance<CollectController>(collect);
  }));
  final info = _Info(collect);
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    navigatorKey: navigator,
    home: InfoPage(
        inputBangumiItem: item ?? _subject(summary: summary),
        infoController: info),
  ));
  await tester.pump();
  expect(info.requests.length, 1);
  return info;
}

Future<void> _complete(WidgetTester tester, _Info info, bool success,
    {bool throws = false}) async {
  if (throws) {
    info.requests.last.completeError(StateError('failed route'));
  } else {
    info.requests.last.complete(success);
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 650));
  await tester.pumpAndSettle();
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

FocusNode _play(WidgetTester tester) =>
    tester.widget<TvDetailActions>(find.byType(TvDetailActions)).playFocus;
FocusNode _retry(WidgetTester tester) => tester
    .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '重试'))
    .focusNode!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late Level oldLogLevel;
  late PathProviderPlatform oldPaths;
  setUpAll(() async {
    oldLogLevel = Logger.level;
    Logger.level = Level.off;
    temp = await Directory.systemTemp.createTemp('tv_metadata_retry_');
    oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(temp.path);
    Hive.init(temp.path);
    await GStorage.init();
  });
  tearDown(() => TvMode.setEnabledForTesting(false));
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = oldPaths;
    await temp.delete(recursive: true);
    Logger.level = oldLogLevel;
  });

  Future<_Info> openFailedCover(WidgetTester tester,
      {bool metadataFails = false}) async {
    final item = _subject(summary: metadataFails ? '' : 'Loaded summary')
      ..images = {'large': 'https://fixture.invalid/remote-cover.png'};
    final info = await _open(tester,
        item: item,
        size: const Size(960, 540),
        theme: ThemeData(
            brightness: metadataFails ? Brightness.dark : Brightness.light));
    await _complete(tester, info, !metadataFails);
    await _exhaustCovers(tester);
    expect(find.text('重试封面'), findsOneWidget);
    return info;
  }

  testWidgets('cover remote 1 exhausted retries: LEFT from play reaches cover',
      (tester) async {
    final cache = _failCovers();
    await openFailedCover(tester);
    expect(cache.calls, 3);
    _play(tester).requestFocus();
    await tester.pump();
    await _key(tester, LogicalKeyboardKey.arrowLeft);
    expect(_coverRetry(tester).hasPrimaryFocus, isTrue);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    for (var i = 0; i < 4; i++) {
      await _key(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '发表吐槽'))
            .focusNode!
            .hasPrimaryFocus,
        isTrue);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(_play(tester).hasPrimaryFocus, isTrue,
        reason: 'last action still wraps right while cover retry is visible');
  });

  testWidgets('cover remote 2 no failure: LEFT wraps to review, RIGHT to play',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    final item = _subject(summary: 'Loaded summary')
      ..images = {'large': 'https://fixture.invalid/loaded-cover.png'};
    final provider = ResizeImage.resizeIfNeeded(
        158,
        null,
        CachedNetworkImageProvider(
            NetworkImgLayer.tvDetailCoverUrl(item.images)));
    final key = await provider.obtainKey(ImageConfiguration.empty);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.white, BlendMode.src);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(2, 3);
    picture.dispose();
    PaintingBinding.instance.imageCache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: image))));
    addTearDown(() {
      NetworkImgLayer.clearTvCoverMemory();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });
    final info = await _open(tester, item: item);
    await _complete(tester, info, true);
    expect(find.text('重试封面'), findsNothing);
    expect(find.byWidgetPredicate((w) => w is RawImage && w.image != null),
        findsOneWidget);
    final play = _play(tester)..requestFocus();
    await tester.pump();
    await _key(tester, LogicalKeyboardKey.arrowLeft);
    expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '发表吐槽'))
            .focusNode!
            .hasPrimaryFocus,
        isTrue);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(play.hasPrimaryFocus, isTrue);
  });

  for (final metadataFails in [false, true]) {
    testWidgets('cover remote 3 directions, info retry=$metadataFails',
        (tester) async {
      _failCovers();
      await openFailedCover(tester, metadataFails: metadataFails);
      final cover = _coverRetry(tester)..requestFocus();
      await tester.pump();
      final button =
          tester.widget<TextButton>(find.widgetWithText(TextButton, '重试封面'));
      final colors = Theme.of(tester.element(find.text('重试封面'))).colorScheme;
      const focused = {WidgetState.focused};
      expect(button.style!.backgroundColor!.resolve(focused), colors.primary);
      expect(button.style!.foregroundColor!.resolve(focused), colors.onPrimary);
      expect(button.style!.side!.resolve(focused)!.width, 3);
      await _key(tester, LogicalKeyboardKey.arrowLeft);
      expect(cover.hasPrimaryFocus, isTrue);
      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(_play(tester).hasPrimaryFocus, isTrue);
      await _key(tester, LogicalKeyboardKey.arrowLeft);
      expect(cover.hasPrimaryFocus, isTrue);
      await _key(tester, LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus!.debugLabel, 'TV detail back');
      cover.requestFocus();
      await tester.pump();
      await _key(tester, LogicalKeyboardKey.arrowDown);
      if (metadataFails) {
        expect(_retry(tester).hasPrimaryFocus, isTrue);
      } else {
        expect(
            FocusManager.instance.primaryFocus!.context!
                .findAncestorWidgetOfExactType<TabBar>(),
            isNotNull);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'cover remote 4 OK hands focus to play before removal and refetches',
      (tester) async {
    final cache = _failCovers();
    await openFailedCover(tester);
    final play = _play(tester);
    final cover = _coverRetry(tester)..requestFocus();
    await tester.pump();
    bool? retryPresentWhenPlayFocused;
    void observeFocus() {
      if (play.hasPrimaryFocus) {
        retryPresentWhenPlayFocused = find.text('重试封面').evaluate().isNotEmpty;
      }
    }

    play.addListener(observeFocus);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _flushCover(tester);
    play.removeListener(observeFocus);
    expect(play.hasPrimaryFocus, isTrue);
    expect(retryPresentWhenPlayFocused, isTrue);
    expect(cover.hasPrimaryFocus, isFalse);
    expect(cache.calls, 4);
    expect(find.text('重试封面'), findsNothing);
    await _exhaustCovers(tester);
    expect(cache.calls, 6);
    expect(find.text('重试封面'), findsOneWidget);
    expect(play.hasPrimaryFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overview 6 stable tag left edge at 960x540 and no overflow',
      (tester) async {
    Future<double?> showTags(List<String> names, String summary) async {
      final item = _subject(summary: summary)
        ..tags = [
          for (final name in names)
            BangumiTag(name: name, count: 2, totalCount: 2),
        ];
      final info = await _open(tester, item: item, size: const Size(960, 540));
      await _complete(tester, info, true);
      expect(tester.takeException(), isNull);
      final x = names.isEmpty ? null : tester.getTopLeft(find.text('标签')).dx;
      if (names.isEmpty) expect(find.text('标签'), findsNothing);
      expect(find.text('阅读完整简介'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      return x;
    }

    final shortX = await showTags(['日常', '喜剧'], 'Short summary');
    final longX = await showTags(
        List.generate(20, (i) => '很长的分类标签和制作信息 $i'), 'Short summary');
    expect(shortX, longX);
    expect(shortX, 16);
    final longSummary = List.filled(2000, '很长的简介内容。').join();
    await showTags([], longSummary);
    expect(tester.takeException(), isNull);
  });

  for (final succeed in [false, true]) {
    test(
        'D13 controller reports API success=$succeed and preserves attached cover',
        () async {
      DioFactory.reset();
      final adapter = _MetadataAdapter(succeed);
      DioFactory.apiDio.httpClientAdapter = adapter;
      addTearDown(() {
        DioFactory.apiDio.close(force: true);
        DioFactory.reset();
      });
      final collect = _Collect();
      final item = _subject(summary: 'Cached summary')
        ..images = {'large': 'https://fixture.invalid/rendered.jpg'};
      final info = InfoController(collect)..bangumiItem = item;
      expect(await info.queryBangumiInfoByID(item.id, type: 'attach'), succeed);
      expect(info.isLoading, isFalse);
      expect(info.bangumiItem, same(item));
      expect(item.images['large'], 'https://fixture.invalid/rendered.jpg');
      expect(item.summary, succeed ? '' : 'Cached summary');
      expect(collect.updates, succeed ? 1 : 0);
      expect(adapter.calls, greaterThanOrEqualTo(1));
    });
  }

  for (final throws in [false, true]) {
    testWidgets(
        'D13 rule 9 failed empty metadata offers retry (throws=$throws)',
        (tester) async {
      final info = await _open(tester);
      expect(find.text('资料加载失败'), findsNothing);
      await _complete(tester, info, false, throws: throws);
      expect(find.text('资料加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('暂无简介'), findsNothing);
    });
  }

  testWidgets('D13 rule 10 successful empty summary remains no summary',
      (tester) async {
    final info = await _open(tester);
    await _complete(tester, info, true);
    expect(find.text('暂无简介'), findsOneWidget);
    expect(find.text('资料加载失败'), findsNothing);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('D13 rule 11 failed refresh preserves cached summary',
      (tester) async {
    final info = await _open(tester, summary: 'Cached summary');
    await _complete(tester, info, false);
    expect(find.text('Cached summary'), findsOneWidget);
    expect(find.text('资料加载失败'), findsNothing);
    expect(find.text('重试'), findsNothing);
  });

  for (final result in ['failure', 'empty', 'summary']) {
    final success = result != 'failure';
    testWidgets('D13 rule 12 retry focus after $result; rule 14 one load',
        (tester) async {
      final info = await _open(tester);
      await _complete(tester, info, false);
      if (result == 'summary') info.nextSummary = 'Fetched summary';
      final retry = _retry(tester);
      retry.requestFocus();
      await tester.pump();
      expect(retry.hasPrimaryFocus, isTrue);
      await _key(tester, LogicalKeyboardKey.select);
      expect(info.requests.length, 2);
      expect(find.text('重试中…'), findsOneWidget);
      expect(find.text('资料加载失败'), findsNothing);
      expect(retry.hasPrimaryFocus, isTrue);
      await _key(tester, LogicalKeyboardKey.select);
      await _key(tester, LogicalKeyboardKey.enter);
      expect(info.requests.length, 2);
      expect(retry.hasPrimaryFocus, isTrue);
      // Early completion must still retain the existing minimum skeleton time.
      bool? retryPresentWhenPlayFocused;
      final play = _play(tester);
      void checkFocus() {
        if (play.hasPrimaryFocus) {
          retryPresentWhenPlayFocused = find.text('重试中…').evaluate().isNotEmpty;
        }
      }

      play.addListener(checkFocus);
      info.requests.last.complete(success);
      await tester.pump();
      expect(find.text('重试中…'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pumpAndSettle();
      if (success) {
        expect(find.text('重试'), findsNothing);
        expect(find.text('重试中…'), findsNothing);
        expect(find.text(result == 'summary' ? 'Fetched summary' : '暂无简介'),
            findsOneWidget);
        expect(_play(tester).hasPrimaryFocus, isTrue);
        expect(retryPresentWhenPlayFocused, isTrue);
      } else {
        expect(find.text('重试'), findsOneWidget);
        expect(retry.hasPrimaryFocus, isTrue);
      }
      play.removeListener(checkFocus);
    });
  }

  testWidgets(
      'D13 rule 13 action DOWN retry, retry UP play, DOWN tabs, sideways stays',
      (tester) async {
    final info = await _open(tester);
    await _complete(tester, info, false);
    final play = _play(tester);
    final retry = _retry(tester);
    play.requestFocus();
    await tester.pump();
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(retry.hasPrimaryFocus, isTrue);
    await _key(tester, LogicalKeyboardKey.arrowLeft);
    expect(retry.hasPrimaryFocus, isTrue);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(retry.hasPrimaryFocus, isTrue);
    await _key(tester, LogicalKeyboardKey.arrowUp);
    expect(play.hasPrimaryFocus, isTrue);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    final tabs = tester.widget<TabBar>(find.byType(TabBar));
    expect(
        FocusManager.instance.primaryFocus!.context!
            .findAncestorWidgetOfExactType<TabBar>(),
        same(tabs));
    expect(tabs.controller!.index, 0);
  });

  testWidgets('D13 rule 13 successful metadata keeps action DOWN to tabs',
      (tester) async {
    final info = await _open(tester);
    await _complete(tester, info, true);
    _play(tester).requestFocus();
    await tester.pump();
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(
        FocusManager.instance.primaryFocus!.context!
            .findAncestorWidgetOfExactType<TabBar>(),
        isNotNull);
  });

  testWidgets('D13 Back from retry pops the normal detail route',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final collect = _Collect();
    bootstrapModule(createModule(
        register: (c) => c.addInstance<CollectController>(collect)));
    final info = _Info(collect);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Home fixture'))));
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) =>
            InfoPage(inputBangumiItem: _subject(), infoController: info)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await _complete(tester, info, false);
    _retry(tester).requestFocus();
    await tester.pumpAndSettle();
    expect(await navigator.currentState!.maybePop(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Home fixture'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('D13 rule 15 mobile failure retains original layout and controls',
      (tester) async {
    final info = await _open(tester, tv: false);
    await _complete(tester, info, false);
    expect(find.byType(TvDetailActions), findsNothing);
    expect(find.byType(CollectButton), findsOneWidget);
    expect(find.text('放送开始:'), findsOneWidget);
    expect(find.text('资料加载失败'), findsNothing);
    expect(find.text('重试'), findsNothing);
    expect(
        tester
            .widget<BangumiInfoCardV>(find.byType(BangumiInfoCardV))
            .tvActions,
        isNull);
    expect(find.widgetWithText(FloatingActionButton, '开始观看'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
