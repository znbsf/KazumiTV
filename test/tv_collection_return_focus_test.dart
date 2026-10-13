import 'package:kazumi/bean/widget/tv_text_entry.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/collect/collect_library_view.dart';
import 'package:kazumi/pages/collect/collect_page.dart';
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

class _Collection extends FocusCollectController {
  @override
  void loadCollectibles() {}
}

CollectedBangumi _entry(int id, {DateTime? time}) => CollectedBangumi(
    focusItem(id),
    time ?? DateTime(2026, 9, 6).subtract(Duration(minutes: id)),
    CollectType.watching.value);

class _App extends StatelessWidget {
  _App({int count = 8}) {
    collection.collectibles.addAll(List.generate(count, (i) => _entry(i + 1)));
    module = createModule(register: (c) {
      c.route('/collect/',
          child: (_, __) => CollectPage(controller: collection));
      c.route('/info/', child: (_, state) {
        opened.add((state.arguments as BangumiItem).id);
        return Scaffold(
            body: Center(
                child: TextButton(
          autofocus: true,
          onPressed: () => rootNavigatorKey.currentState!.maybePop(),
          child: const Text('返回收藏'),
        )));
      });
    });
  }
  final collection = _Collection();
  final opened = <int>[];
  late final Module module;
  @override
  Widget build(BuildContext context) => ModularApp(
      module: module,
      initialRoute: '/collect/',
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [rootRouteObserver, KazumiDialog.observer],
      child: Builder(
          builder: (context) => MaterialApp.router(
              theme: ThemeData(platform: TargetPlatform.android),
              routerConfig: ModularApp.routerConfigOf(context))));
}

Finder _card(int id) => find.byKey(ValueKey('collect-$id'));
FocusNode _focus(WidgetTester tester, int id) {
  final target = tester.element(_card(id));
  return FocusManager.instance.rootScope.descendants.firstWhere((node) {
    if (node is FocusScopeNode ||
        !node.canRequestFocus ||
        node.context == null) {
      return false;
    }
    var inside = false;
    (node.context! as Element).visitAncestorElements((element) {
      if (element == target) inside = true;
      return !inside;
    });
    return inside;
  });
}

ScrollController _scroll(WidgetTester tester) => tester
    .widget<CustomScrollView>(find.descendant(
        of: find.byType(CollectLibraryView),
        matching: find.byType(CustomScrollView)))
    .controller!;

Future<_App> _mount(WidgetTester tester, {int count = 8}) async {
  tester.view.physicalSize = const Size(960, 540);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final app = _App(count: count);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  return app;
}

Future<void> _open(WidgetTester tester, int id) async {
  _focus(tester, id).requestFocus();
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
  expect(find.text('返回收藏'), findsOneWidget);
}

Future<void> _back(WidgetTester tester) async {
  await rootNavigatorKey.currentState!.maybePop();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  setUpAll(() async {
    temporary = await Directory.systemTemp.createTemp('kazumi_collect_return_');
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

  testWidgets('collection detail return keeps subject after sorted reordering',
      (tester) async {
    final app = await _mount(tester);
    await _open(tester, 2);
    app.collection.collectibles.replaceRange(
        0,
        8,
        [1, 3, 2, 4, 5, 6, 7, 8].asMap().entries.map((entry) => _entry(
            entry.value,
            time:
                DateTime(2026, 9, 6).subtract(Duration(minutes: entry.key)))));
    await tester.pumpAndSettle();
    await _back(tester);
    expect(_focus(tester, 2).hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(app.opened.last, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collection return preserves first visible id and pixel offset',
      (tester) async {
    final app = await _mount(tester, count: 40);
    final scroll = _scroll(tester);
    scroll.jumpTo(800);
    await tester.pumpAndSettle();
    final viewport = tester.getRect(find.descendant(
        of: find.byType(CollectLibraryView),
        matching: find.byType(CustomScrollView)));
    final visible = List.generate(40, (i) => i + 1)
        .where((id) =>
            _card(id).evaluate().isNotEmpty &&
            tester.getRect(_card(id)).overlaps(viewport))
        .toList();
    final anchor = visible.first;
    final selected = visible.length > 2 ? visible[2] : visible.last;
    _focus(tester, selected).requestFocus();
    await tester.pumpAndSettle();
    final anchorTop = tester.getTopLeft(_card(anchor)).dy;
    await _open(tester, selected);
    app.collection.collectibles.insertAll(0, [
      _entry(101, time: DateTime(2026, 9, 7)),
      _entry(102, time: DateTime(2026, 9, 7))
    ]);
    await tester.pumpAndSettle();
    await _back(tester);
    expect(_focus(tester, selected).hasPrimaryFocus, isTrue);
    expect(tester.getTopLeft(_card(anchor)).dy, closeTo(anchorTop, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'collection missing return chooses anchor then empty search action',
      (tester) async {
    final app = await _mount(tester);
    await _open(tester, 2);
    app.collection.collectibles
        .removeWhere((entry) => entry.bangumiItem.id == 2);
    await tester.pumpAndSettle();
    await _back(tester);
    expect(_focus(tester, 1).hasPrimaryFocus, isTrue);
    await _open(tester, 1);
    app.collection.collectibles.clear();
    await tester.pumpAndSettle();
    await _back(tester);
    final search = tester.widget<TvTextEntry>(find.byType(TvTextEntry)).child;
    expect(search.focusNode?.hasPrimaryFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collection return realizes selected subject moved offscreen',
      (tester) async {
    final app = await _mount(tester, count: 60);
    await _open(tester, 2);
    app.collection.collectibles[1] = _entry(2, time: DateTime(2025));
    await tester.pumpAndSettle();
    await _back(tester);
    expect(_focus(tester, 2).hasPrimaryFocus, isTrue);
    expect(
        tester.getRect(_card(2)).overlaps(const Rect.fromLTWH(0, 0, 960, 540)),
        isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(app.opened.last, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collection new filter cancels an in-flight detail return',
      (tester) async {
    final app = await _mount(tester);
    final search = tester.widget<TvTextEntry>(find.byType(TvTextEntry)).child;
    await _open(tester, 2);
    await rootNavigatorKey.currentState!.maybePop();
    // Public search UI callback wins before the return realization frame.
    search.controller!.text = '番剧 7';
    search.onChanged!('番剧 7');
    search.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    expect(find.text('本地测试番剧 7'), findsOneWidget);
    expect(_card(2), findsNothing);
    expect(search.focusNode!.hasPrimaryFocus, isTrue);
    expect(app.opened, [2]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty collection sort left reaches search navigation and cancel',
      (tester) async {
    final app = await _mount(tester, count: 0);
    tester.view.physicalSize = const Size(1920, 1080);
    await tester.pumpAndSettle();
    final sync = Focus.of(tester.element(find.byIcon(Icons.sync_rounded)));
    final sort = Focus.of(tester.element(find.byIcon(Icons.sort_rounded)));
    final search = tester.widget<TvTextEntry>(find.byType(TvTextEntry)).child;
    sync.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(sort.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(search.focusNode!.hasPrimaryFocus, isTrue);
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tv-text-editor')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('tv-text-editor')), 'draft');
    tester.testTextInput.hide();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(search.controller!.text, isEmpty);
    expect(search.focusNode!.hasPrimaryFocus, isTrue);
    expect(app.opened, isEmpty);
    expect(app.collection.collectibles, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty collection sidebar categories retain vertical navigation',
      (tester) async {
    await _mount(tester, count: 0);
    tester.view.physicalSize = const Size(1920, 1080);
    await tester.pumpAndSettle();
    final search = tester.widget<TvTextEntry>(find.byType(TvTextEntry)).child;
    final all = Focus.of(tester.element(find.descendant(
        of: find.byKey(const ValueKey('collect-filter-all')),
        matching: find.byIcon(Icons.video_library_outlined))));
    final watching = Focus.of(tester.element(find.descendant(
        of: find.byKey(const ValueKey('collect-filter-1')),
        matching: find.byIcon(Icons.play_circle_outline_rounded))));
    all.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(watching.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(all.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(search.focusNode!.hasPrimaryFocus, isTrue);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('non TV collection keeps direct SearchBar editing',
      (tester) async {
    TvMode.setEnabledForTesting(false);
    await _mount(tester, count: 0);
    expect(find.byType(TvTextEntry), findsNothing);
    final search = tester.widget<SearchBar>(find.byType(SearchBar));
    search.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
