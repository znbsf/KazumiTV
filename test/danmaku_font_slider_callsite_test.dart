import 'package:kazumi/bean/widget/tv_focus_navigation.dart';
import 'package:kazumi/bean/widget/connected_tabs.dart';
import 'dart:io';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/pages/settings/danmaku/danmaku_settings.dart';
import 'package:kazumi/pages/settings/danmaku/danmaku_settings_sheet.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _LiveOptions implements DanmakuController {
  DanmakuOption value = DanmakuOption(fontSize: 24);
  @override
  DanmakuOption get option => value;
  @override
  ValueChanged<DanmakuOption> get updateOption => (next) {
        value = next;
      };
  @override
  dynamic noSuchMethod(Invocation i) => throw UnsupportedError('$i');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('danmaku_font_step_');
    PathProviderPlatform.instance = _Paths(temp.path);
    Hive.init(temp.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });
  tearDown(() => TvMode.setEnabledForTesting(false));
  testWidgets('actual playback appearance first slider up reaches tabs',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _LiveOptions();
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) =>
            FocusTraversalGroup(policy: TvLoopTraversalPolicy(), child: child!),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showDanmakuSettingsSheet(
                        context: context,
                        danmakuController: controller,
                        onUpdateDanmakuSpeed: () {}),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final slider = find.byType(Slider).first;
    final focus = tester
        .widget<FocusableActionDetector>(find
            .descendant(
                of: slider, matching: find.byType(FocusableActionDetector))
            .first)
        .focusNode!;
    focus.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(
        FocusManager.instance.primaryFocus!.context!
            .findAncestorWidgetOfExactType<ConnectedTabs>(),
        isNotNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final opacity in [false, true]) {
    for (final sheet in [false, true]) {
      for (final tv in [true, false]) {
        testWidgets(
            'actual ${sheet ? "playback sheet" : "standalone"} ${opacity ? 'opacity' : 'fontsize'} TV=$tv',
            (tester) async {
          TvMode.setEnabledForTesting(tv);
          tester.view.physicalSize = const Size(1280, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.runAsync(() => GStorage.putSetting(
              opacity
                  ? SettingsKeys.danmakuOpacity
                  : SettingsKeys.danmakuFontSize,
              opacity ? 1.0 : 24.0));
          final controller = _LiveOptions();
          if (sheet) {
            await tester.pumpWidget(MaterialApp(
                home: Builder(
                    builder: (context) => Scaffold(
                        body: TextButton(
                            onPressed: () => showDanmakuSettingsSheet(
                                context: context,
                                danmakuController: controller,
                                onUpdateDanmakuSpeed: () {}),
                            child: const Text('Open'))))));
            await tester.tap(find.text('Open'));
            await tester.pumpAndSettle();
          } else {
            await tester.pumpWidget(MaterialApp(
                home: SettingsPaneScope(
                    embedded: true,
                    showBackButton: false,
                    onBack: () {},
                    child: const DanmakuSettingsPage())));
            await tester.pumpAndSettle();
          }
          final tile = find.byWidgetPredicate((w) =>
              w is SettingsSliderTile &&
              w.title is Text &&
              (w.title as Text).data ==
                  (opacity ? (sheet ? '不透明度' : '弹幕不透明度') : '字体大小'));
          if (!sheet) {
            await tester.scrollUntilVisible(tile, 450,
                scrollable: find
                    .descendant(
                        of: find.byType(DanmakuSettingsPage),
                        matching: find.byType(Scrollable))
                    .first);
          }
          await tester.ensureVisible(tile);
          await tester.pumpAndSettle();
          final slider =
              find.descendant(of: tile, matching: find.byType(Slider));
          expect(slider, findsOneWidget);
          if (tv) {
            final focus = find
                .descendant(
                    of: slider, matching: find.byType(FocusableActionDetector))
                .first;
            tester
                .widget<FocusableActionDetector>(focus)
                .focusNode!
                .requestFocus();
            await tester.pumpAndSettle();
            Future<void> key(LogicalKeyboardKey key) async {
              await tester.runAsync(() async {
                await tester.sendKeyEvent(key);
                await Hive.box('setting').flush();
              });
              await tester.pumpAndSettle();
            }

            await key(LogicalKeyboardKey.arrowLeft);
            expect(
                GStorage.getSetting(opacity
                    ? SettingsKeys.danmakuOpacity
                    : SettingsKeys.danmakuFontSize),
                opacity ? .95 : 23.0);
            expect(tester.widget<Slider>(slider).value, opacity ? .95 : 23.0);
            if (sheet) {
              expect(
                  opacity
                      ? controller.value.opacity
                      : controller.value.fontSize,
                  opacity ? .95 : 23.0);
            }
            await key(LogicalKeyboardKey.arrowRight);
            expect(
                GStorage.getSetting(opacity
                    ? SettingsKeys.danmakuOpacity
                    : SettingsKeys.danmakuFontSize),
                opacity ? 1.0 : 24.0);
            expect(tester.widget<Slider>(slider).value, opacity ? 1.0 : 24.0);
            if (sheet) {
              expect(
                  opacity
                      ? controller.value.opacity
                      : controller.value.fontSize,
                  opacity ? 1.0 : 24.0);
            }
            // Exact endpoints must not overshoot or lose one unit when reversing.
            Future<void> setValue(double value) async {
              await tester.runAsync(() async {
                tester.widget<Slider>(slider).onChanged!(value);
                await Hive.box('setting').flush();
              });
              await tester.pumpAndSettle();
            }

            final low = tester.widget<Slider>(slider).min;
            final high = tester.widget<Slider>(slider).max;
            final step = opacity ? .05 : 1.0;
            await setValue(low);
            await key(LogicalKeyboardKey.arrowLeft);
            expect(tester.widget<Slider>(slider).value, low);
            await key(LogicalKeyboardKey.arrowRight);
            expect(tester.widget<Slider>(slider).value,
                closeTo(low + step, 1e-10));
            await setValue(high);
            await key(LogicalKeyboardKey.arrowRight);
            expect(tester.widget<Slider>(slider).value, high);
            await key(LogicalKeyboardKey.arrowLeft);
            expect(tester.widget<Slider>(slider).value,
                closeTo(high - step, 1e-10));
            await setValue(opacity ? 1.0 : 24.0);
            // Up/down must only navigate, not mutate this integer setting.
            await key(LogicalKeyboardKey.arrowUp);
            expect(
                GStorage.getSetting(opacity
                    ? SettingsKeys.danmakuOpacity
                    : SettingsKeys.danmakuFontSize),
                opacity ? 1.0 : 24.0);
          } else {
            expect(tester.widget<Slider>(slider).divisions, isNull);
            await tester.runAsync(() async {
              tester.widget<Slider>(slider).onChanged!(opacity ? .954 : 24.9);
              await Hive.box('setting').flush();
            });
            await tester.pumpAndSettle();
            expect(
                GStorage.getSetting(opacity
                    ? SettingsKeys.danmakuOpacity
                    : SettingsKeys.danmakuFontSize),
                opacity ? .95 : 24.0,
                reason:
                    'non-TV continuous touch keeps its original floor policy');
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        });
      }
    }
  }
}
