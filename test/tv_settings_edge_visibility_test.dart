import 'package:kazumi/pages/player/controller/player_super_resolution.dart';
import 'package:kazumi/pages/settings/super_resolution_settings.dart';
import 'dart:io';
import 'package:kazumi/pages/settings/sync/bangumi_sync_page.dart';
import 'package:kazumi/pages/settings/download_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/bean/widget/tv_focus_navigation.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/pages/settings/danmaku/danmaku_settings.dart';

class Paths extends PathProviderPlatform {
  Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('settings_edge_');
    PathProviderPlatform.instance = Paths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  testWidgets('download explanation remains reachable below final switch',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    addTearDown(() => TvMode.setEnabledForTesting(false));
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
                child: const DownloadSettingsPage()))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('缓存弹幕'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.text('缓存弹幕'))).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final explanation = find.text('关于并发设置');
    expect(Focus.of(tester.element(explanation)).hasPrimaryFocus, isTrue);
    final rect = FocusManager.instance.primaryFocus!.rect;
    expect(rect.top, greaterThanOrEqualTo(56));
    expect(rect.bottom, lessThanOrEqualTo(540));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(find.text('缓存弹幕'))).hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
        FocusManager.instance.primaryFocus!.context!
            .findAncestorWidgetOfExactType<Slider>(),
        isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(explanation)).hasPrimaryFocus, isTrue,
        reason: 'Reversing a wrap must return to the actual final row');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Bangumi bottom wrap reveals complete account header',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    addTearDown(() => TvMode.setEnabledForTesting(false));
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
                child: const BangumiSyncPage()))));
    await tester.pumpAndSettle();
    final preferences = find.text('同步偏好');
    await tester.ensureVisible(preferences);
    Focus.of(tester.element(preferences)).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final header = find.text('连接 Bangumi 账号');
    expect(Focus.of(tester.element(header)).hasPrimaryFocus, isTrue);
    final rect = FocusManager.instance.primaryFocus!.rect;
    expect(rect.top, greaterThanOrEqualTo(64));
    expect(rect.bottom, lessThanOrEqualTo(540));
    expect(tester.getRect(header).top, greaterThanOrEqualTo(64));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Bangumi priority arrows navigate without saving a selection',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    addTearDown(() => TvMode.setEnabledForTesting(false));
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final before = GStorage.getSetting(SettingsKeys.bangumiSyncPriority);
    await tester.pumpWidget(MaterialApp(
        home: FocusTraversalGroup(
            policy: TvLoopTraversalPolicy(),
            child: SettingsPaneScope(
                embedded: true,
                showBackButton: false,
                onBack: () {},
                child: const BangumiSyncPage()))));
    await tester.pumpAndSettle();
    final preferences = find.text('同步偏好');
    await tester.ensureVisible(preferences);
    await tester.tap(preferences);
    await tester.pumpAndSettle();
    final first = find.text('以本机为准');
    await tester.ensureVisible(first);
    Focus.of(tester.element(first)).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(GStorage.getSetting(SettingsKeys.bangumiSyncPriority), before);
    expect(
        Focus.of(tester.element(find.text('以 Bangumi 为准'))).hasFocus, isTrue);
    final rect = FocusManager.instance.primaryFocus!.rect;
    expect(rect.top, greaterThanOrEqualTo(64));
    expect(rect.bottom, lessThanOrEqualTo(540));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(first)).hasFocus, isTrue);
    expect(GStorage.getSetting(SettingsKeys.bangumiSyncPriority), before);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('super-resolution edge navigation never selects inner radios',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    addTearDown(() => TvMode.setEnabledForTesting(false));
    await tester.runAsync(() => GStorage.putSetting(
        SettingsKeys.defaultSuperResolutionMode,
        SuperResolutionMode.off.storageValue));
    await tester.runAsync(() =>
        GStorage.putSetting(SettingsKeys.disableSuperResolutionWarning, false));
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
                child: const SuperResolutionSettings()))));
    await tester.pumpAndSettle();
    final last = find.text('关闭提示');
    await tester.ensureVisible(last);
    Focus.of(tester.element(last)).requestFocus();
    await tester.pumpAndSettle();
    for (var cycle = 0; cycle < 3; cycle++) {
      for (final label in ['关闭', '效率档', '质量档', '关闭提示']) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(
            Focus.of(tester.element(find.text(label))).hasPrimaryFocus, isTrue,
            reason: 'Down must focus the complete row: $label');
        expect(GStorage.getSetting(SettingsKeys.defaultSuperResolutionMode),
            SuperResolutionMode.off.storageValue);
        expect(GStorage.getSetting(SettingsKeys.disableSuperResolutionWarning),
            false);
      }
    }
    for (final label in ['质量档', '效率档', '关闭', '关闭提示']) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(Focus.of(tester.element(find.text(label))).hasPrimaryFocus, isTrue,
          reason: label);
      expect(GStorage.getSetting(SettingsKeys.defaultSuperResolutionMode),
          SuperResolutionMode.off.storageValue);
    }
    await tester.runAsync(() => tester.sendKeyEvent(LogicalKeyboardKey.enter));
    await tester.runAsync(() => Hive.box('setting').flush());
    await tester.pumpAndSettle();
    expect(
        GStorage.getSetting(SettingsKeys.disableSuperResolutionWarning), true);
    await tester.runAsync(() => tester.sendKeyEvent(LogicalKeyboardKey.enter));
    await tester.runAsync(() => Hive.box('setting').flush());
    await tester.pumpAndSettle();
    expect(
        GStorage.getSetting(SettingsKeys.disableSuperResolutionWarning), false);
    Focus.of(tester.element(find.text('效率档'))).requestFocus();
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.sendKeyEvent(LogicalKeyboardKey.enter));
    await tester.runAsync(() => Hive.box('setting').flush());
    await tester.pumpAndSettle();
    expect(GStorage.getSetting(SettingsKeys.defaultSuperResolutionMode),
        SuperResolutionMode.efficiency.storageValue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => GStorage.putSetting(
        SettingsKeys.defaultSuperResolutionMode,
        SuperResolutionMode.off.storageValue));
  });
  for (final up in [false, true]) {
    testWidgets(
        'real danmaku ${up ? "top" : "bottom"} wrap reveals the focused setting',
        (tester) async {
      TvMode.setEnabledForTesting(true);
      addTearDown(() => TvMode.setEnabledForTesting(false));
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
                  child: const DanmakuSettingsPage()))));
      await tester.pumpAndSettle();
      final state =
          tester.state<ScrollableState>(find.byType(Scrollable).first);
      if (!up) {
        state.position.jumpTo(state.position.maxScrollExtent);
        await tester.pumpAndSettle();
        state.position.jumpTo(state.position.maxScrollExtent);
        await tester.pumpAndSettle();
      }
      final reset =
          Focus.of(tester.element(find.text(up ? 'BiliBili' : '恢复默认设置')));
      reset.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(
          up ? LogicalKeyboardKey.arrowUp : LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final destination = find.text(up ? '恢复默认设置' : 'BiliBili');
      expect(destination, findsOneWidget);
      expect(Focus.of(tester.element(destination)).hasFocus, isTrue,
          reason: 'Wrap must reach the actual opposite page edge');
      final rect = FocusManager.instance.primaryFocus!.rect;
      debugPrint('WRAPPED FOCUS RECT $rect');
      expect(rect.top, greaterThanOrEqualTo(56),
          reason: 'Wrapped focus must be revealed below fixed header');
      expect(rect.bottom, lessThanOrEqualTo(540));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
