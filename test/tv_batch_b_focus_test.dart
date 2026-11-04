import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:mobx/mobx.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/tv_focusable_surface.dart';
import 'package:kazumi/bean/widget/tv_text_entry.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/modules/search/image_search_module.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/collect/collect_library_view.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/download/download_page.dart';
import 'package:kazumi/pages/history/tv_history_grid.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/pages/info/info_page.dart';
import 'package:kazumi/pages/info/rating_review_dialog.dart';
import 'package:kazumi/pages/info/source_health_page.dart';
import 'package:kazumi/pages/info/source_sheet.dart';
import 'package:kazumi/pages/search/image_search_page.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/player/history_playback_service.dart';
import 'package:kazumi/services/plugin/captcha_verification_service.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'source_health_test.dart' show FakeRule;
import 'support/tv_focus_fixtures.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Captcha extends CaptchaVerificationService {
  @override
  Future<void> loadForCaptcha(String url, String captchaXpath,
      {String? inputXpath}) async {}
  @override
  Future<void> cancelAndSave(String pluginName) async {}
}

class _Images extends FocusSearchController {
  final done = Completer<void>();
  String outcome = 'success';
  @override
  Future<void> searchImageByUrl(String url) async {
    isImageSearching = true;
    await done.future;
    if (outcome == 'success') {
      imageSearchResults.add(ResultItem(filename: 'Match', similarity: .99));
    } else {
      imageSearchError = outcome == 'empty' ? '未找到匹配结果' : 'failed';
    }
    isImageSearching = false;
  }
}

class _Downloads implements DownloadController {
  _Downloads(int count) {
    snapshots['test_1'] = DownloadRecord(
        1,
        'Show',
        '',
        'test',
        {
          for (var i = 1; i <= count; i++)
            i: DownloadEpisode(i, 'Episode $i', 0, DownloadStatus.paused, .1,
                100, 10, '', '', '', null, '', 0, 'url/$i')
        },
        DateTime(2026));
  }
  final snapshots = ObservableMap<String, DownloadRecord>();
  @override
  ObservableList<String> get recordKeys => ObservableList.of(snapshots.keys);
  @override
  void refreshRecords() {}
  @override
  DownloadRecord? getRecordSnapshot(String key) => snapshots[key];
  @override
  double getSpeed(int id, String plugin, int episode) => 0;
  @override
  Future<void> deleteEpisode(int id, String plugin, int episode) async {
    final record = snapshots['test_1']!;
    record.episodes.remove(episode);
    if (record.episodes.isEmpty) {
      snapshots.remove('test_1');
    } else {
      snapshots['test_1'] = DownloadRecord(
          id, 'Show', '', plugin, Map.of(record.episodes), DateTime(2026));
    }
  }

  @override
  Future<void> deleteRecord(int id, String plugin) async {
    snapshots.remove('test_1');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

FocusNode _textFocus(WidgetTester tester, String label) {
  final text = find.text(label).last;
  final surfaces = find.ancestor(of: text, matching: find.byType(TvFocusableSurface));
  if (surfaces.evaluate().isNotEmpty) {
    final node = tester.widget<TvFocusableSurface>(surfaces.first).focusNode;
    if (node != null) return node;
  }
  return Focus.of(tester.element(text));
}
FocusNode _entryFocus(WidgetTester tester, Finder entry) => tester
    .widget<TvFocusableSurface>(
        find.descendant(of: entry, matching: find.byType(TvFocusableSurface)))
    .focusNode!;

Future<void> _mount(WidgetTester tester, Widget page,
    {CollectController? collect, PluginsController? plugins}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ModularApp(
      module: createModule(register: (c) {
        c.addInstance<CollectController>(collect ?? FocusCollectController());
        c.addInstance<HistoryPlaybackService>(FocusPlaybackService());
        c.addInstance<PluginsController>(plugins ?? PluginsController());
        c.route('/', child: (_, __) => page);
      }),
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [KazumiDialog.observer],
      child: Builder(
          builder: (context) => MaterialApp.router(
              routerConfig: ModularApp.routerConfigOf(context)))));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late PathProviderPlatform paths;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('tv_batch_b_');
    paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(temp.path);
    Hive.init(temp.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = paths;
    await temp.delete(recursive: true);
  });
  setUp(() {
    Logger.level = Level.off;
    TvMode.setEnabledForTesting(true);
  });
  tearDown(() => TvMode.setEnabledForTesting(false));

  testWidgets('I-3 source health return restores its own action',
      (tester) async {
    final collect = FocusCollectController();
    await _mount(
        tester,
        InfoPage(
            inputBangumiItem: focusItem(1),
            infoController: InfoController(collect)),
        collect: collect);
    final health = _textFocus(tester, '源健康 · 实验功能');
    health.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byType(SourceHealthPage), findsOneWidget);
    await rootNavigatorKey.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(health.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byType(SourceHealthPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('I-8 leaving source results hands focus to source header',
      (tester) async {
    final rule = FakeRule('source')
      ..search = () async => PluginSearchResponse(pluginName: 'source', data: [
            SearchItem(name: 'one', src: '/1'),
            SearchItem(name: 'two', src: '/2')
          ]);
    final info = InfoController(FocusCollectController())
      ..bangumiItem = focusItem(1);
    await _mount(tester, SourceSheet(infoController: info),
        plugins: PluginsController()..pluginList.add(rule));
    // TV shows all results directly. Left replaces the old collapse footer.
    _textFocus(tester, 'two').requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_textFocus(tester, 'source').hasPrimaryFocus, isTrue);
  });

  testWidgets('I-8 retry keeps focus on header while content is pending',
      (tester) async {
    final pending = Completer<PluginSearchResponse>();
    final rule = FakeRule('source')
      ..search = () async => throw Exception('failed');
    final info = InfoController(FocusCollectController())
      ..bangumiItem = focusItem(1);
    await _mount(tester, SourceSheet(infoController: info),
        plugins: PluginsController()..pluginList.add(rule));
    rule.search = () => pending.future;
    _textFocus(tester, '重试').requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_textFocus(tester, 'source').hasPrimaryFocus, isTrue);
    pending.complete(PluginSearchResponse(pluginName: 'source', data: []));
    await tester.pumpAndSettle();
    expect(_textFocus(tester, 'source').hasPrimaryFocus, isTrue);
  });

  for (final cancel in ['button', 'back']) {
    testWidgets('I-9 captcha $cancel returns without another search',
        (tester) async {
      final rule = FakeRule('source')
        ..search = () async => throw CaptchaRequiredException('source');
      final info = InfoController(FocusCollectController())
        ..bangumiItem = focusItem(1);
      await _mount(
          tester,
          SourceSheet(
              infoController: info,
              createCaptchaVerificationService: _Captcha.new),
          plugins: PluginsController()..pluginList.add(rule));
      await tester.tap(find.text('进行验证'));
      await tester.pump(const Duration(milliseconds: 300));
      if (cancel == 'button') {
        await tester.tap(find.text('返回来源'));
      } else {
        await rootNavigatorKey.currentState!.maybePop();
      }
      await tester.pumpAndSettle();
      expect(rule.calls, 1);
      expect(find.text('重试'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(rule.calls, 2);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('I-16 review initially focuses comment and failure focuses retry',
      (tester) async {
    await _mount(
        tester,
        RatingReviewDialog(
            bangumiItem: focusItem(1), onSubmit: (_) async => false));
    expect(_entryFocus(tester, find.byType(TvTextEntry).first).hasPrimaryFocus,
        isTrue);
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.tap(find.text('发表'));
    await tester.pumpAndSettle();
    expect(_textFocus(tester, '重试').hasPrimaryFocus, isTrue);
  });

  testWidgets('I-18 start check transfers focus to cancel', (tester) async {
    final pending = Completer<PluginSearchResponse>();
    final rule = FakeRule('source')..search = () => pending.future;
    await _mount(
        tester,
        SourceHealthPage(
            subject: focusItem(1),
            plugins: [rule],
            persistRecord: (_) async {}));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 200));
    expect(_textFocus(tester, '取消并返回').hasPrimaryFocus, isTrue);
    pending.complete(PluginSearchResponse(pluginName: 'source', data: []));
    await tester.pumpAndSettle();
  });

  testWidgets('S-3 custom tag suffix restores input entry focus',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(FocusFixtureApp(initialRoute: '/search/'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.tune_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('题材标签'));
    await tester.pumpAndSettle();
    final entry = find.byType(TvTextEntry).first;
    tester.widget<TvTextEntry>(entry).child.controller!.text = 'custom';
    final suffix = find.byTooltip('添加标签');
    Focus.of(tester
            .element(find.descendant(of: suffix, matching: find.byType(Icon))))
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_entryFocus(tester, entry).hasPrimaryFocus, isTrue);
    expect(tester.widget<TvTextEntry>(entry).child.controller!.text, isEmpty);
  });

  for (final outcome in ['success', 'empty', 'failure']) {
    testWidgets('S-5 recognition $outcome has stable busy and completion focus',
        (tester) async {
      final images = _Images()..outcome = outcome;
      await _mount(tester, ImageSearchPage(controller: images));
      await tester.tap(find.text('图片链接'));
      await tester.pumpAndSettle();
      final field = tester.widget<TvTextEntry>(find.byType(TvTextEntry)).child;
      field.controller!.text = 'https://example.invalid/frame.png';
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      _textFocus(tester, '开始识别').requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 400));
      expect(_textFocus(tester, '正在识别').hasPrimaryFocus, isTrue);
      images.done.complete();
      await tester.pumpAndSettle();
      expect(
          _textFocus(tester, outcome == 'success' ? '搜索这部番' : '开始识别')
              .hasPrimaryFocus,
          isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final outcome in ['cancel', 'failure']) {
    testWidgets('S-5 image picker $outcome restores pick action',
        (tester) async {
      final pending = Completer<String?>();
      const channel = MethodChannel('plugins.flutter.io/image_picker');
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) => pending.future);
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      await _mount(tester, ImageSearchPage(controller: _Images()));
      _textFocus(tester, '选择截图').requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 300));
      // Model the external activity taking window focus.
      FocusManager.instance.primaryFocus?.unfocus();
      if (outcome == 'cancel') {
        pending.complete(null);
      } else {
        pending.completeError(PlatformException(code: 'denied'));
      }
      await tester.pumpAndSettle();
      expect(_textFocus(tester, '选择截图').hasPrimaryFocus, isTrue);
    });
  }

  for (final index in [0, 1, 2]) {
    testWidgets(
        'C-1 changed status restores neighbor or category at index $index',
        (tester) async {
      var entries = List.generate(
          index + 1,
          (i) => CollectedBangumi(
              focusItem(i + 1),
              DateTime(2026).subtract(Duration(minutes: i)),
              CollectType.watching.value));
      await _mount(
          tester,
          StatefulBuilder(
              builder: (context, rebuild) => Scaffold(
                  body: CollectLibraryView(
                      entries: entries,
                      showRating: false,
                      onOpen: (_) {},
                      canEdit: (_) => true,
                      onChangeType: (item, type) => rebuild(() {
                            entries = entries
                                .where((e) => e.bangumiItem.id != item.id)
                                .toList();
                          })))));
      final id = index == 2 ? 2 : index + 1;
      final card = find.byKey(ValueKey('collect-$id'));
      await tester
          .tap(find.descendant(of: card, matching: find.byType(FilledButton)));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, '看过'));
      await tester.pumpAndSettle();
      if (index == 0) {
        expect(_textFocus(tester, '在看').hasPrimaryFocus, isTrue);
      } else {
        final nextId = index == 2 ? 3 : 1;
        final target = find.descendant(
            of: find.byKey(ValueKey('collect-$nextId')),
            matching: find
                .byWidgetPredicate((w) => w is InkWell && w.focusNode != null));
        expect(
            tester.widget<InkWell>(target).focusNode!.hasPrimaryFocus, isTrue);
      }
    });
  }

  for (final count in [1, 2]) {
    testWidgets(
        'D-6 delete defaults cancel and restores target with $count episodes',
        (tester) async {
      final downloads = _Downloads(count);
      await _mount(tester, DownloadPage(controller: downloads));
      await tester.tap(find.byTooltip('删除').first);
      await tester.pumpAndSettle();
      expect(_textFocus(tester, '取消').hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(downloads.snapshots['test_1']!.episodes.length, count);
      await tester.tap(find.byTooltip('删除').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '删除'));
      await tester.pumpAndSettle();
      if (count == 2) {
        final icon = find.descendant(
            of: find.byTooltip('删除'), matching: find.byType(Icon));
        expect(Focus.of(tester.element(icon)).hasPrimaryFocus, isTrue);
      } else {
        expect(
            FocusManager.instance.primaryFocus, isNot(isA<FocusScopeNode>()));
        expect(FocusManager.instance.primaryFocus?.context, isNotNull);
      }
    });
  }

  testWidgets(
      'D-6 delete record defaults cancel and restores next record header',
      (tester) async {
    final downloads = _Downloads(1);
    downloads.snapshots['test_2'] = DownloadRecord(2, 'Next show', '', 'test',
        Map.of(downloads.snapshots['test_1']!.episodes), DateTime(2026));
    await _mount(tester, DownloadPage(controller: downloads));
    await tester.tap(find.byTooltip('更多操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部删除'));
    await tester.pumpAndSettle();
    expect(_textFocus(tester, '取消').hasPrimaryFocus, isTrue);
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();
    expect(_textFocus(tester, 'Next show').hasPrimaryFocus, isTrue);
  });

  for (final width in [800.0, 1280.0]) {
    testWidgets('H-1 history columns use constrained content width $width',
        (tester) async {
      await _mount(
          tester,
          Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                  width: width,
                  child: TvHistoryGrid(
                      entries: FocusHistoryRepository(count: 8).items,
                      editing: false,
                      onDelete: (_) async {}))));
      final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
      expect(
          (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
              .crossAxisCount,
          width == 800 ? 1 : 2);
    });
  }
}
