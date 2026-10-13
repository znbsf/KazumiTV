import 'package:kazumi/bean/widget/tv_focus_navigation.dart';
import 'package:kazumi/pages/settings/keyboard_settings.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/widget/numeric_shortcut_visibility.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/pages/settings/tv_remote_help.dart';
import 'package:kazumi/pages/player/player_keyboard_shortcuts.dart';
import 'package:kazumi/utils/constants.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('shortcut_audit_');
    PathProviderPlatform.instance = _Paths(temp.path);
    Hive.init(temp.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });
  tearDown(() => TvMode.setEnabledForTesting(false));
  testWidgets('TV keyboard first up reaches actual last action and reverses',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: FocusTraversalGroup(
            policy: TvLoopTraversalPolicy(),
            child: SettingsPaneScope(
                embedded: true,
                showBackButton: false,
                onBack: () {},
                child: const KeyboardSettingsPage()))));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final badge = find.byKey(const ValueKey('numeric-shortcut-badges-setting'));
    FocusNode badgeFocus() => Focus.of(tester.element(find
        .descendant(of: badge, matching: find.byType(AnimatedScale))
        .first));
    badgeFocus().requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    final last = find.byKey(const ValueKey('shortcut-add-speeddown'));
    expect(last, findsOneWidget);
    final lastIcon = find.descendant(of: last, matching: find.byType(Icon));
    expect(Focus.of(tester.element(lastIcon)).hasPrimaryFocus, isTrue);
    expect(FocusManager.instance.primaryFocus!.rect.bottom,
        lessThanOrEqualTo(540));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(badgeFocus().hasPrimaryFocus, isTrue);
    expect(
        FocusManager.instance.primaryFocus!.rect.top, greaterThanOrEqualTo(56));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'editor records, cancels, deletes, restores and reopens saved keys',
      (tester) async {
    for (final entry in defaultShortcuts.entries) {
      await tester.runAsync(() => GStorage.putStringListSettingByName(
          'shortcut_${entry.key}', entry.value));
    }
    Widget editor() => MaterialApp(
        home: SettingsPaneScope(
            embedded: true,
            showBackButton: false,
            onBack: () {},
            child: const KeyboardSettingsPage()));
    await tester.pumpWidget(editor());
    await tester.pumpAndSettle();
    final first = find.byKey(const ValueKey('shortcut-playorpause-0'));
    await tester.tap(first);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.runAsync(() => tester.sendKeyEvent(LogicalKeyboardKey.keyQ));
    await tester.pumpAndSettle();
    expect(GStorage.getStringListSettingByName('shortcut_playorpause'), ['Q']);
    await tester.tap(find.byKey(const ValueKey('shortcut-add-playorpause')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.runAsync(() => tester.sendKeyEvent(LogicalKeyboardKey.escape));
    await tester.pumpAndSettle();
    expect(GStorage.getStringListSettingByName('shortcut_playorpause'), ['Q']);
    await tester.tap(find.byKey(const ValueKey('shortcut-add-playorpause')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.runAsync(() => tester.sendKeyEvent(LogicalKeyboardKey.keyW));
    await tester.pumpAndSettle();
    expect(GStorage.getStringListSettingByName('shortcut_playorpause'),
        ['Q', 'W']);
    final delete =
        find.descendant(of: first, matching: find.byType(IconButton));
    expect(delete, findsOneWidget);
    final deleteFocus = Focus.of(tester
        .element(find.descendant(of: delete, matching: find.byType(Icon))));
    deleteFocus.requestFocus();
    await tester.pump();
    await tester.runAsync(() => tester.sendKeyEvent(LogicalKeyboardKey.enter));
    await tester.pumpAndSettle();
    expect(GStorage.getStringListSettingByName('shortcut_playorpause'), ['W']);
    await tester.runAsync(() => Hive.box('setting').flush());
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(editor());
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('shortcut-playorpause-0')),
            matching: find.text('W')),
        findsOneWidget);
    await tester.runAsync(
        () => tester.tap(find.byIcon(Icons.settings_backup_restore_rounded)));
    await tester.pumpAndSettle();
    expect(GStorage.getStringListSettingByName('shortcut_playorpause'),
        defaultShortcuts['playorpause']);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'numeric hint setting updates all visible hints and survives reopening without intercepting digits',
      (tester) async {
    expect(SettingsKeys.showNumericShortcutBadges.defaultValue, true);
    await tester.runAsync(() =>
        GStorage.putSetting(SettingsKeys.showNumericShortcutBadges, true));
    var digits = 0;
    Widget screen() => MaterialApp(
        home: Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.digit1) {
                digits++;
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: const Column(children: [
              NumericShortcutVisibility(child: Text('poster hint 1')),
              NumericShortcutVisibility(child: Text('poster hint 2')),
              Text('LCN 011'),
              Text('Episode 1')
            ])));
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('poster hint 1'), findsOneWidget);
    await tester.runAsync(() =>
        GStorage.putSetting(SettingsKeys.showNumericShortcutBadges, false));
    await tester.pumpAndSettle();
    expect(find.text('poster hint 1'), findsNothing);
    expect(find.text('poster hint 2'), findsNothing);
    expect(find.text('LCN 011'), findsOneWidget);
    expect(find.text('Episode 1'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    expect(digits, 1);
    await tester.runAsync(() => Hive.box('setting').flush());
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('poster hint 1'), findsNothing);
    final saved = await tester.runAsync(() async {
      final bytes = await File('${temp.path}/setting.hive').readAsBytes();
      final copied = await Hive.openBox<dynamic>('shortcut-settings-disk-check',
          bytes: bytes);
      final value = copied.get(SettingsKeys.showNumericShortcutBadges.name);
      await copied.close();
      return value;
    });
    expect(saved, false,
        reason: 'read a fresh Hive box from flushed disk bytes');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    expect(digits, 2);
    await tester.runAsync(() =>
        GStorage.putSetting(SettingsKeys.showNumericShortcutBadges, true));
    await tester.pumpAndSettle();
    expect(find.text('poster hint 1'), findsOneWidget);
    expect(find.text('poster hint 2'), findsOneWidget);
  });

  testWidgets(
      'TV recording rejects fixed or duplicate keys and Back cancels without leaving',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    for (final entry in defaultShortcuts.entries) {
      await tester.runAsync(() => GStorage.putStringListSettingByName(
          'shortcut_${entry.key}', entry.value));
    }
    await tester.pumpWidget(MaterialApp(
        home: SettingsPaneScope(
            embedded: true,
            showBackButton: false,
            onBack: () {},
            child: const KeyboardSettingsPage())));
    await tester.pumpAndSettle();
    final tab = find.byWidgetPredicate((w) =>
        w is Focus && w.focusNode?.debugLabel == 'TV custom shortcuts section');
    tester.widget<Focus>(tab).focusNode!.requestFocus();
    await tester.pumpAndSettle();
    final cap = find.byKey(const ValueKey('shortcut-playorpause-0'));
    await tester.ensureVisible(cap);
    await tester.pumpAndSettle();
    final ink = find.descendant(of: cap, matching: find.byType(InkWell)).first;
    // Reach/activate the actual keycap by remote focus, then attempt reserved INFO.
    Focus.of(tester.element(
            find.descendant(of: ink, matching: find.byType(Text)).first))
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.runAsync(() => tester.sendKeyEvent(LogicalKeyboardKey.info));
    await tester.pumpAndSettle();
    expect(GStorage.getStringListSettingByName('shortcut_playorpause'), [' ']);
    await tester.runAsync(() => tester.sendKeyEvent(LogicalKeyboardKey.keyN));
    await tester.pumpAndSettle();
    expect(GStorage.getStringListSettingByName('shortcut_playorpause'), [' ']);
    await tester.runAsync(() => tester.binding.handlePopRoute());
    await tester.pumpAndSettle();
    expect(find.byType(KeyboardSettingsPage), findsOneWidget);
    expect(GStorage.getStringListSettingByName('shortcut_playorpause'), [' ']);
    expect(find.textContaining('返回取消'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test('fixed TV aliases cannot be hijacked by persisted custom bindings', () {
    final result = withTvRemoteShortcuts({
      'screenshot': [
        LogicalKeyboardKey.select.keyLabel,
        LogicalKeyboardKey.info.keyLabel
      ],
      'playorpause': [LogicalKeyboardKey.arrowDown.keyLabel]
    });
    expect(result['screenshot'],
        isNot(contains(LogicalKeyboardKey.select.keyLabel)));
    expect(result['screenshot'],
        isNot(contains(LogicalKeyboardKey.info.keyLabel)));
    expect(result['playorpause'],
        isNot(contains(LogicalKeyboardKey.arrowDown.keyLabel)));
    expect(result['showdetails'], contains(LogicalKeyboardKey.info.keyLabel));
  });
  testWidgets(
      'every custom action consumes persisted edits without recreating player',
      (tester) async {
    final scope = FocusScopeNode();
    addTearDown(scope.dispose);
    final calls = <String>[];
    for (final entry in defaultShortcuts.entries) {
      await tester.runAsync(() => GStorage.putStringListSettingByName(
          'shortcut_${entry.key}', entry.value));
    }
    await tester.pumpWidget(MaterialApp(
        home: FocusScope(
            node: scope,
            child: Column(children: [
              PlayerKeyboardShortcuts(focusScopeNode: scope, actions: {
                for (final action in defaultShortcuts.keys)
                  action: () {
                    calls.add(action);
                  }
              }),
              const Focus(autofocus: true, child: SizedBox())
            ]))));
    await tester.pump();
    for (final action in defaultShortcuts.keys) {
      calls.clear();
      await tester.runAsync(
          () => GStorage.putStringListSettingByName('shortcut_$action', ['Q']));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
      await tester.pump();
      expect(calls, [action],
          reason: '$action must consume the saved key immediately');
      await tester.runAsync(() => GStorage.putStringListSettingByName(
          'shortcut_$action', defaultShortcuts[action]!));
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('remote help traverses individual rows to bottom and back out',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      TextButton(onPressed: () {}, child: const Text('Exit guide')),
      Expanded(
          child: ListView(controller: scroll, children: const [TvRemoteHelp()]))
    ]))));
    await tester.pumpAndSettle();
    final first = find.byKey(const ValueKey('tv-remote-help-item-0-0'));
    expect(first, findsOneWidget);
    final row = find.descendant(of: first, matching: find.byType(ListTile));
    Focus.of(tester.element(row)).requestFocus();
    await tester.pumpAndSettle();
    for (var i = 0; i < 15; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(scroll.offset, greaterThan(400));
    for (var i = 0; i < 17; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
    }
    expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<TextButton>(),
        isNotNull);
    expect(tester.takeException(), isNull);
  });
}
