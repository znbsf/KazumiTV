import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:kazumi/bean/widget/tv_focusable_surface.dart';
import 'package:kazumi/bean/widget/tv_player_side_panel.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/info/source_sheet.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

SourceSearchGroup _group(String name,
        {int results = 0,
        PluginSearchStatus status = PluginSearchStatus.success,
        bool unsearched = false}) =>
    SourceSearchGroup(
      name: name,
      keyword: 'title',
      status: status,
      unsearched: unsearched,
      results: [
        for (var i = 0; i < results; i++)
          SearchItem(name: '$name result $i', src: '/$i'),
      ],
    );

Widget _view(List<SourceSearchGroup> groups,
        {String? first,
        List<String>? calls,
        ValueChanged<String>? onKeyword,
        VoidCallback? onClose}) =>
    SourceSheetView(
      keyword: 'title',
      groups: groups,
      firstResultSource: first,
      onSourceSearch: (name) {
        calls?.add('keyword:$name');
        onKeyword?.call(name);
      },
      onSourceAliasSearch: (name) => calls?.add('alias:$name'),
      onRetry: (name) => calls?.add('retry:$name'),
      onVerify: (name) => calls?.add('verify:$name'),
      onOpenBrowser: (name) => calls?.add('browser:$name'),
      onPlay: (name, result) => calls?.add('play:$name:${result.src}'),
      onClose: onClose ?? () {},
    );

Future<void> _frames(WidgetTester tester) async {
  // Pending searches have a continuous loading animation.
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _mount(WidgetTester tester, Widget view,
    {Size size = const Size(960, 540), double scale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: (size.width * .66).clamp(560.0, 760.0).toDouble(),
          child: view,
        ),
      ),
    ),
  ));
  await _frames(tester);
}

FocusNode _focus(WidgetTester tester, String text) {
  final label = find.text(text);
  final surfaces = find.ancestor(of: label, matching: find.byType(TvFocusableSurface));
  if (surfaces.evaluate().isNotEmpty) {
    final node = tester.widget<TvFocusableSurface>(surfaces.first).focusNode;
    if (node != null) return node;
  }
  return Focus.of(tester.element(label));
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await _frames(tester);
}

void _expectVisibleFocus(WidgetTester tester) {
  final node = FocusManager.instance.primaryFocus!;
  expect(node, isNot(isA<FocusScopeNode>()));
  final rect = node.context!.findRenderObject() as RenderBox;
  final bounds = rect.localToGlobal(Offset.zero) & rect.size;
  final viewport = tester.getRect(find.byKey(const ValueKey('tv-source-columns')));
  expect(bounds.left, greaterThanOrEqualTo(viewport.left - .1));
  expect(bounds.right, lessThanOrEqualTo(viewport.right + .1));
  expect(bounds.top, greaterThanOrEqualTo(viewport.top - .1));
  expect(bounds.bottom, lessThanOrEqualTo(viewport.bottom + .1));
}

void main() {
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() => TvMode.setEnabledForTesting(false));

  testWidgets('first completed result source starts selected and focused; OK plays',
      (tester) async {
    final calls = <String>[];
    await _mount(tester,
        _view([_group('A', results: 2), _group('B', results: 2)], first: 'B', calls: calls));
    expect(find.text('A result 0'), findsNothing);
    expect(_focus(tester, 'B result 0').hasPrimaryFocus, isTrue);
    await _key(tester, LogicalKeyboardKey.select);
    expect(calls, ['play:B:/0']);
    await _key(tester, LogicalKeyboardKey.arrowLeft);
    expect(_focus(tester, 'B').hasPrimaryFocus, isTrue);
    await _key(tester, LogicalKeyboardKey.arrowUp);
    expect(_focus(tester, 'A').hasPrimaryFocus, isTrue);
    expect(find.text('B result 0'), findsNothing);
    expect(find.text('A result 0'), findsOneWidget);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(_focus(tester, 'A result 0').hasPrimaryFocus, isTrue);
    await _key(tester, LogicalKeyboardKey.arrowLeft);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(_focus(tester, 'B').hasPrimaryFocus, isTrue);
    expect(find.text('B result 0'), findsOneWidget);
  });

  const actions = [
    '修改此来源的检索词',
    '使用别名检索此来源',
    '重新检索此来源',
    '在浏览器中打开',
  ];
  for (var index = 0; index < actions.length; index++) {
    testWidgets('OK on source row opens menu and dispatches ${actions[index]}',
        (tester) async {
      final calls = <String>[];
      await _mount(tester, _view([_group('A', results: 1)], first: 'A', calls: calls));
      await _key(tester, LogicalKeyboardKey.arrowLeft);
      await _key(tester, LogicalKeyboardKey.select);
      for (final action in actions) {
        expect(find.widgetWithText(MenuItemButton, action), findsOneWidget);
      }
      expect(_focus(tester, actions.first).hasPrimaryFocus, isTrue);
      for (var down = 0; down < index; down++) {
        await _key(tester, LogicalKeyboardKey.arrowDown);
      }
      await _key(tester, LogicalKeyboardKey.select);
      expect(calls, ['${['keyword', 'alias', 'retry', 'browser'][index]}:A']);
      expect(find.byType(MenuItemButton), findsNothing);
      expect(_focus(tester, 'A').hasPrimaryFocus, isTrue);
    });
  }

  testWidgets('menu restoration does not take focus from the next dialog', (tester) async {
    final dialogFocus = FocusNode();
    addTearDown(dialogFocus.dispose);
    await _mount(tester, Builder(builder: (context) => _view(
      [_group('A', results: 1)], first: 'A', onKeyword: (_) {
        showDialog<void>(context: context, builder: (context) => AlertDialog(
          title: const Text('Keyword dialog'),
          content: TextButton(focusNode: dialogFocus, autofocus: true,
            onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        ));
      },
    )));
    await _key(tester, LogicalKeyboardKey.arrowLeft);
    await _key(tester, LogicalKeyboardKey.select);
    await _key(tester, LogicalKeyboardKey.select);
    expect(find.text('Keyword dialog'), findsOneWidget);
    expect(dialogFocus.hasPrimaryFocus, isTrue);
    await _key(tester, LogicalKeyboardKey.select);
    expect(_focus(tester, 'A').hasPrimaryFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('late responses do not move header or open-menu focus', (tester) async {
    late StateSetter update;
    var groups = [_group('A', status: PluginSearchStatus.pending)];
    await _mount(tester, StatefulBuilder(builder: (_, setState) {
      update = setState;
      return _view(groups, first: groups.first.hasResults ? 'A' : null);
    }));
    final close = Focus.of(tester.element(find.byIcon(Icons.close_rounded)));
    close.requestFocus();
    await tester.pump();
    update(() => groups = [_group('A', results: 1)]);
    await _frames(tester);
    expect(close.hasPrimaryFocus, isTrue);
    _focus(tester, 'A').requestFocus();
    await tester.pump();
    await _key(tester, LogicalKeyboardKey.select);
    final menuFocus = FocusManager.instance.primaryFocus;
    update(() => groups = [_group('A', results: 2)]);
    await _frames(tester);
    expect(FocusManager.instance.primaryFocus, same(menuFocus));
    expect(find.byType(MenuItemButton), findsNWidgets(4));
  });

  testWidgets('late results and source reorder retain selection and row focus',
      (tester) async {
    late StateSetter update;
    var groups = [_group('A', status: PluginSearchStatus.pending), _group('B')];
    String? first;
    await _mount(tester, StatefulBuilder(builder: (_, setState) {
      update = setState;
      return _view(groups, first: first);
    }));
    final initial = _focus(tester, 'A');
    expect(initial.hasPrimaryFocus, isTrue);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    final selected = _focus(tester, 'B');
    update(() {
      groups = [_group('B'), _group('A', results: 1)];
      first = 'A';
    });
    await _frames(tester);
    expect(_focus(tester, 'B'), same(selected));
    expect(selected.hasPrimaryFocus, isTrue);
    expect(find.text('A result 0'), findsNothing);
    expect(find.text('没有找到匹配结果'), findsOneWidget);
    update(() => groups = [_group('B', results: 2), _group('A', results: 1)]);
    await _frames(tester);
    expect(selected.hasPrimaryFocus, isTrue);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    final result = _focus(tester, 'B result 0');
    update(() {
      final b = _group('B', results: 3);
      groups = [_group('A', results: 1), SourceSearchGroup(
        name: b.name, keyword: b.keyword, status: b.status,
        results: b.results.reversed.toList(),
      )];
    });
    await _frames(tester);
    expect(_focus(tester, 'B result 0'), same(result));
    expect(result.hasPrimaryFocus, isTrue);
    _expectVisibleFocus(tester);
  });

  for (final status in [PluginSearchStatus.error, PluginSearchStatus.captcha,
    PluginSearchStatus.noResult]) {
    testWidgets('$status actions are reachable from the selected source', (tester) async {
      final calls = <String>[];
      await _mount(tester, _view([_group('A', status: status)], calls: calls));
      expect(_focus(tester, 'A').hasPrimaryFocus, isTrue);
      await _key(tester, LogicalKeyboardKey.arrowRight);
      await _key(tester, LogicalKeyboardKey.select);
      expect(calls, ['${switch (status) {
        PluginSearchStatus.error => 'retry',
        PluginSearchStatus.captcha => 'verify',
        _ => 'keyword',
      }}:A']);
      expect(_focus(tester, 'A').hasPrimaryFocus, isTrue);
    });
  }

  testWidgets('unsearched source offers search without starting it on focus', (tester) async {
    final calls = <String>[];
    await _mount(tester, _view([_group('A', unsearched: true)], calls: calls));
    expect(calls, isEmpty);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(_focus(tester, '搜索 A').hasPrimaryFocus, isTrue);
    await _key(tester, LogicalKeyboardKey.select);
    expect(calls, ['retry:A']);
  });

  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('TV two columns scroll focused items into view at $size / $scale', (tester) async {
        var groups = [for (var i = 0; i < 12; i++) _group('Source $i', results: 16)];
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Builder(builder: (context) => Scaffold(body: TextButton(
            onPressed: () => showAdaptiveBottomSheet<void>(
              context: context, tvWide: true,
              builder: (_) => _view(groups,
                  first: groups.first.hasResults ? groups.first.name : null),
            ),
            child: const Text('Open'),
          ))),
        ));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(TvPlayerSidePanel)).width,
            closeTo(size.width == 960 ? 633.6 : 760, .1));
        _expectVisibleFocus(tester);
        for (var i = 0; i < 15; i++) {
          await _key(tester, LogicalKeyboardKey.arrowDown);
          _expectVisibleFocus(tester);
        }
        expect(_focus(tester, 'Source 0 result 15').hasPrimaryFocus, isTrue);
        await _key(tester, LogicalKeyboardKey.arrowLeft);
        for (var i = 0; i < 11; i++) {
          await _key(tester, LogicalKeyboardKey.arrowDown);
          _expectVisibleFocus(tester);
        }
        expect(_focus(tester, 'Source 11').hasPrimaryFocus, isTrue);
        await _key(tester, LogicalKeyboardKey.arrowRight);
        expect(_focus(tester, 'Source 11 result 0').hasPrimaryFocus, isTrue);
        _expectVisibleFocus(tester);
        expect(tester.takeException(), isNull);
        await _key(tester, LogicalKeyboardKey.escape);
        expect(find.byType(SourceSheetView), findsNothing);
        for (final state in [
          _group('Source', status: PluginSearchStatus.noResult),
          _group('Source', status: PluginSearchStatus.error),
          _group('Source', status: PluginSearchStatus.captcha),
          _group('Source', unsearched: true),
          _group('Source', status: PluginSearchStatus.pending),
        ]) {
          groups = [state];
          await tester.tap(find.text('Open'));
          await _frames(tester);
          _expectVisibleFocus(tester);
          await _key(tester, LogicalKeyboardKey.arrowRight);
          _expectVisibleFocus(tester);
          await _key(tester, LogicalKeyboardKey.arrowLeft);
          expect(_focus(tester, 'Source').hasPrimaryFocus, isTrue);
          expect(tester.takeException(), isNull);
          await _key(tester, LogicalKeyboardKey.escape);
        }
      });
    }
  }

  testWidgets('wide option applies only on TV; menu Back returns to source before closing', (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => showAdaptiveBottomSheet<void>(
        context: context, tvWide: true,
        builder: (context) => _view([_group('A', results: 1)], first: 'A',
          onClose: () => Navigator.of(context).pop()),
      ), child: const Text('Open')),
    ))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(TvPlayerSidePanel)).width, closeTo(633.6, .1));
    await _key(tester, LogicalKeyboardKey.arrowLeft);
    await _key(tester, LogicalKeyboardKey.select);
    await _key(tester, LogicalKeyboardKey.escape);
    expect(find.byType(MenuItemButton), findsNothing);
    expect(_focus(tester, 'A').hasPrimaryFocus, isTrue);
    expect(find.byType(SourceSheetView), findsOneWidget);
    await _key(tester, LogicalKeyboardKey.escape);
    expect(find.byType(SourceSheetView), findsNothing);
  });

  testWidgets('wide option leaves non-TV modal width unchanged', (tester) async {
    TvMode.setEnabledForTesting(false);
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => showAdaptiveBottomSheet<void>(
        context: context, tvWide: true,
        builder: (_) => const SizedBox(height: 120, child: Text('Sheet body')),
      ), child: const Text('Open')),
    ))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(TvPlayerSidePanel), findsNothing);
    expect(tester.getSize(find.text('Sheet body')).width, closeTo(640, .1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-TV preserves single list and only previews first result source', (tester) async {
    TvMode.setEnabledForTesting(false);
    await _mount(tester, _view([_group('A', results: 2), _group('B', results: 2)], first: 'B'));
    expect(find.byKey(const ValueKey('tv-source-columns')), findsNothing);
    expect(find.byType(TvFocusableSurface), findsNothing);
    expect(find.byType(PopupMenuButton<VoidCallback>), findsNWidgets(2));
    expect(find.text('A result 0'), findsNothing);
    expect(find.text('B result 0'), findsOneWidget);
    expect(find.text('B result 1'), findsNothing);
    await tester.tap(find.text('展开全部 2 个结果'));
    await tester.pumpAndSettle();
    expect(find.text('B result 1'), findsOneWidget);
  });
}
