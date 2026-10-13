import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/widget/tv_range_slider.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('kazumi_range_filter_');
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });
  testWidgets('TV search filter values survive apply and reopen',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    addTearDown(() => TvMode.setEnabledForTesting(false));
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.predidit.kazumi/tv_navigation'),
            (_) async => null);
    final app = FocusFixtureApp(initialRoute: '/search/');
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.tune_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpansionTile).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile).at(1));
    await tester.pumpAndSettle();
    final saved = <RangeValues>[];
    for (var i = 0; i < 2; i++) {
      final wrapper = find.byType(TvRangeSlider).at(i);
      final buttons =
          find.descendant(of: wrapper, matching: find.byType(TextButton));
      tester.widget<TextButton>(buttons.first).focusNode!.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      saved.add(tester.widget<TvRangeSlider>(wrapper).child.values);
    }
    expect(saved[0], const RangeValues(7.5, 9.5));
    expect(saved[1], const RangeValues(101, 4900));
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();
    expect(find.byType(TvRangeSlider), findsNothing);
    await tester.tap(find.byIcon(Icons.tune_rounded).first);
    await tester.pumpAndSettle();
    expect(find.byType(TvRangeSlider), findsNWidgets(2));
    for (var i = 0; i < 2; i++) {
      expect(
          tester
              .widget<TvRangeSlider>(find.byType(TvRangeSlider).at(i))
              .child
              .values,
          saved[i]);
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'expanded date group exposes its first control after reverse traversal',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    addTearDown(() => TvMode.setEnabledForTesting(false));
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(FocusFixtureApp(initialRoute: '/search/'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.tune_rounded).first);
    await tester.pumpAndSettle();
    final date = find.byType(ExpansionTile).at(1);
    final scoreTitle =
        tester.widget<ExpansionTile>(find.byType(ExpansionTile).at(2)).title;
    Focus.of(tester.element(find.byWidget(scoreTitle))).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final dropdown = find.descendant(
        of: date, matching: find.byType(DropdownButtonFormField<String>));
    expect(dropdown, findsOneWidget);
    expect(
        FocusManager.instance.primaryFocus!.context!
            .findAncestorWidgetOfExactType<DropdownButtonFormField<String>>(),
        isNotNull);
    expect(tester.takeException(), isNull);
  });
}
