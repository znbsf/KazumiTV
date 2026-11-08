import 'dart:io';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:mobx/mobx.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:kazumi/bean/dialog/tv_panel_page_host.dart';
import 'package:kazumi/bean/widget/tv_player_side_panel.dart';
import 'package:kazumi/bean/widget/tv_text_form_entry.dart';
import 'package:kazumi/bean/widget/tv_visuals.dart';
import 'package:kazumi/pages/my/my_controller.dart';
import 'package:kazumi/pages/player/controller/player_syncplay_controller.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/player/syncplay_sheet.dart';
import 'package:kazumi/pages/settings/danmaku/danmaku_settings_sheet.dart';
import 'package:kazumi/pages/settings/danmaku/danmaku_shield_settings_sheet.dart';
import 'package:kazumi/pages/settings/danmaku/danmaku_time_offset_sheet.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/storage/storage.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Rules implements MyController {
  @override
  final shieldList = ObservableList<String>();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Danmaku implements DanmakuController {
  @override
  DanmakuOption get option => DanmakuOption(fontSize: 24);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SyncState implements PlayerSyncPlayController {
  @override
  bool get hasSession => false;
  @override
  String get syncplayRoom => '';
  @override
  int get syncplayClientRtt => 0;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player implements PlayerController {
  @override
  final syncplay = _SyncState();
  final rooms = <String>[];
  @override
  Future<void> createSyncPlayRoom(String room, String username,
      Future<void> Function(int episode, {int currentRoad, int offset}) changeEpisode) async {
    rooms.add(room);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Routes extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late PathProviderPlatform oldPaths;
  setUpAll(() async {
    oldPaths = PathProviderPlatform.instance;
    temp = await Directory.systemTemp.createTemp('tv_panel_stack_');
    PathProviderPlatform.instance = _Paths(temp.path);
    Hive.init(temp.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = oldPaths;
    await temp.delete(recursive: true);
  });
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() => TvMode.setEnabledForTesting(false));

  Future<void> mount(WidgetTester tester, FocusNode opener, _Routes routes,
      void Function(BuildContext) open,
      {Size size = const Size(960, 540), double scale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ModularApp(
      module: createModule(register: (c) => c.addInstance<MyController>(_Rules())),
      child: MaterialApp(
        theme: TvVisuals.theme(ThemeData.dark()),
        navigatorObservers: [routes],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(builder: (context) => Scaffold(body: TextButton(
          focusNode: opener,
          onPressed: () => open(context),
          child: const Text('Open'),
        ))),
      ),
    ));
    opener.requestFocus();
    await tester.pump();
    await _key(tester, LogicalKeyboardKey.enter);
    expect(routes.pushes, 2); // Home plus exactly one modal route.
  }

  for (final removeEntry in [false, true]) {
    testWidgets('nested Back restores ${removeEntry ? "fallback" : "entry"}; '
        'offstage pages cannot reclaim focus', (tester) async {
      final opener = FocusNode();
      final first = FocusNode();
      final entry = FocusNode();
      final child = FocusNode();
      final leaf = FocusNode();
      for (final node in [opener, first, entry, child, leaf]) {
        addTearDown(node.dispose);
      }
      final routes = _Routes();
      var showEntry = true;
      late StateSetter updateRoot;
      await mount(tester, opener, routes,
          (context) => showAdaptiveBottomSheet<void>(
            context: context,
            builder: (context) => StatefulBuilder(
              builder: (context, setState) {
                updateRoot = setState;
                return Column(mainAxisSize: MainAxisSize.min, children: [
                  TextButton(focusNode: first, onPressed: () {},
                      child: const Text('Fallback')),
                  if (showEntry)
                    TextButton(
                      focusNode: entry,
                      onPressed: () => TvPanelPageHost.of(context).push(
                        (context) => TextButton(
                          focusNode: child,
                          onPressed: () => TvPanelPageHost.of(context).push(
                            (_) => TextButton(focusNode: leaf, onPressed: () {},
                                child: const Text('Leaf')),
                          ),
                          child: const Text('Child'),
                        ),
                      ),
                      child: const Text('Entry'),
                    ),
                ]);
              },
            ),
          ));
      expect(first.hasPrimaryFocus, isTrue);
      entry.requestFocus();
      await tester.pump();
      await _key(tester, LogicalKeyboardKey.enter);
      expect(child.hasPrimaryFocus, isTrue);
      expect(entry.canRequestFocus, isFalse);
      await _key(tester, LogicalKeyboardKey.enter);
      expect(leaf.hasPrimaryFocus, isTrue);
      expect(child.canRequestFocus, isFalse);
      entry.requestFocus();
      child.requestFocus();
      await tester.pumpAndSettle();
      expect(leaf.hasPrimaryFocus, isTrue);
      await _key(tester, LogicalKeyboardKey.escape);
      expect(find.text('Leaf'), findsNothing);
      expect(find.text('Child'), findsOneWidget);
      expect(child.hasPrimaryFocus, isTrue);
      expect(entry.canRequestFocus, isFalse);
      if (removeEntry) {
        updateRoot(() => showEntry = false);
        await tester.pumpAndSettle();
      }
      await _key(tester, LogicalKeyboardKey.escape);
      expect(find.text('Child'), findsNothing);
      expect(find.text('Fallback'), findsOneWidget);
      expect((removeEntry ? first : entry).hasPrimaryFocus, isTrue);
      expect(routes.pushes, 2);
      await _key(tester, LogicalKeyboardKey.escape);
      expect(find.byType(TvPlayerSidePanel), findsNothing);
      expect(opener.hasPrimaryFocus, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    for (final scale in [1.0, 1.3]) {
      for (final shield in [true, false]) {
        testWidgets('danmaku ${shield ? "shield" : "offset"} Back at $size / $scale',
            (tester) async {
          final opener = FocusNode();
          addTearDown(opener.dispose);
          final routes = _Routes();
          await mount(tester, opener, routes, (context) => showDanmakuSettingsSheet(
            context: context,
            danmakuController: _Danmaku(),
            onUpdateDanmakuSpeed: () {},
          ), size: size, scale: scale);
          await tester.tap(find.text('播放'));
          await tester.pumpAndSettle();
          final entry = find.text(shield ? '屏蔽规则' : '时间校准');
          await tester.ensureVisible(entry);
          await tester.pumpAndSettle();
          final entryFocus = Focus.of(tester.element(entry));
          entryFocus.requestFocus();
          await tester.pump();
          await _key(tester, LogicalKeyboardKey.enter);
          expect(find.byType(shield ? DanmakuShieldSettingsSheet : DanmakuTimeOffsetSheet),
              findsOneWidget);
          expect(routes.pushes, 2);
          expect(tester.takeException(), isNull);
          await _key(tester, LogicalKeyboardKey.escape);
          expect(find.text('弹幕设置'), findsOneWidget);
          expect(entryFocus.hasPrimaryFocus, isTrue);
          expect(tester.getRect(entry).bottom, lessThanOrEqualTo(size.height));
          await _key(tester, LogicalKeyboardKey.escape);
          expect(find.byType(TvPlayerSidePanel), findsNothing);
          expect(opener.hasPrimaryFocus, isTrue);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        });
      }

      testWidgets('syncplay server Back restores entry at $size / $scale',
          (tester) async {
        final opener = FocusNode();
        addTearDown(opener.dispose);
        final routes = _Routes();
        await mount(tester, opener, routes, (context) => showSyncPlaySheet(context,
          playerController: _Player(),
          changeEpisode: (episode, {currentRoad = 0, offset = 0}) async {},
        ), size: size, scale: scale);
        final entry = find.text('同步服务器');
        final entryFocus = Focus.of(tester.element(entry));
        entryFocus.requestFocus();
        await tester.pump();
        await _key(tester, LogicalKeyboardKey.enter);
        expect(find.text('房间成员需使用同一服务器'), findsOneWidget);
        expect(routes.pushes, 2);
        expect(tester.takeException(), isNull);
        // maybePop follows the same page stack as the remote Back key.
        await Navigator.of(tester.element(find.text('保存'))).maybePop();
        await tester.pumpAndSettle();
        expect(find.text('和朋友同步看番'), findsOneWidget);
        expect(entryFocus.hasPrimaryFocus, isTrue);
        await _key(tester, LogicalKeyboardKey.enter);
        expect(find.text('房间成员需使用同一服务器'), findsOneWidget);
        await _key(tester, LogicalKeyboardKey.escape);
        expect(find.text('和朋友同步看番'), findsOneWidget);
        expect(entryFocus.hasPrimaryFocus, isTrue);
        expect(routes.pushes, 2);
        await _key(tester, LogicalKeyboardKey.escape);
        expect(find.byType(TvPlayerSidePanel), findsNothing);
        expect(opener.hasPrimaryFocus, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  for (final action in ['创建并加入', '加入房间', '保存', '取消', '关闭']) {
    testWidgets('syncplay subpage $action closes the whole flow', (tester) async {
      final opener = FocusNode();
      addTearDown(opener.dispose);
      final player = _Player();
      final routes = _Routes();
      await mount(tester, opener, routes, (context) => showSyncPlaySheet(context,
        playerController: player,
        changeEpisode: (episode, {currentRoad = 0, offset = 0}) async {},
      ));
      final entry = find.text(switch (action) {
        '创建并加入' => '创建房间',
        '加入房间' => '加入房间',
        _ => '同步服务器',
      });
      Focus.of(tester.element(entry)).requestFocus();
      await tester.pump();
      await _key(tester, LogicalKeyboardKey.enter);
      if (action == '加入房间') {
        tester.widget<TvTextFormEntry>(find.byType(TvTextFormEntry).first)
            .controller.text = '12345678';
        await tester.pumpAndSettle();
      }
      final button = action == '关闭'
          ? find.byIcon(Icons.close_rounded)
          : action == '加入房间'
              ? find.text(action).last
              : find.text(action);
      await tester.ensureVisible(button);
      Focus.of(tester.element(button)).requestFocus();
      await tester.pump();
      await tester.runAsync(() async {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await Hive.box('setting').flush();
      });
      await tester.pumpAndSettle();
      expect(routes.pushes, 2);
      expect(find.byType(TvPlayerSidePanel), findsNothing);
      expect(opener.hasPrimaryFocus, isTrue);
      expect(player.rooms.length,
          action == '创建并加入' || action == '加入房间' ? 1 : 0);
      if (action == '加入房间') expect(player.rooms.single, '12345678');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('non-TV syncplay still closes the parent before opening a step',
      (tester) async {
    TvMode.setEnabledForTesting(false);
    final opener = FocusNode();
    addTearDown(opener.dispose);
    final routes = _Routes();
    await mount(tester, opener, routes, (context) => showSyncPlaySheet(context,
      playerController: _Player(),
      changeEpisode: (episode, {currentRoad = 0, offset = 0}) async {},
    ));
    await tester.tap(find.text('同步服务器'));
    await tester.pumpAndSettle();
    expect(routes.pushes, 3);
    expect(find.text('和朋友同步看番'), findsNothing);
    await Navigator.of(tester.element(find.text('保存'))).maybePop();
    await tester.pumpAndSettle();
    expect(find.text('保存'), findsNothing);
    expect(find.text('和朋友同步看番'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
