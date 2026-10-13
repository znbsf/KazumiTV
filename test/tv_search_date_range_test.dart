import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/bean/widget/tv_text_entry.dart';
import 'package:kazumi/bean/widget/tv_focusable_surface.dart';
import 'package:kazumi/pages/search/search_page.dart';
import 'package:kazumi/pages/search/search_controller.dart';
import 'package:kazumi/repositories/collect_repository.dart';
import 'package:kazumi/repositories/search_history_repository.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/storage/storage.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Future<void> _open(WidgetTester tester, {bool tv = true}) async {
  TvMode.setEnabledForTesting(tv);
  addTearDown(() => TvMode.setEnabledForTesting(false));
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller =
      SearchPageController(CollectRepository(), SearchHistoryRepository());
  await tester
      .pumpWidget(MaterialApp(home: SearchPage(controller: controller)));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.tune_rounded));
  await tester.pumpAndSettle();
  await tester.tap(find.text('放送时间'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('自定义日期'));
  await tester.pumpAndSettle();
  final origin = Focus.of(tester.element(find.text('自定义日期')));
  origin.requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

FocusNode _entryFocus(WidgetTester tester, String key) => tester
    .widget<TvFocusableSurface>(find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(TvFocusableSurface)))
    .focusNode!;

Future<void> _edit(WidgetTester tester, String key, String value,
    {bool cancel = false}) async {
  final entry = _entryFocus(tester, key);
  entry.requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
  final editor = find.byKey(const Key('tv-text-editor'));
  expect(editor, findsOneWidget);
  expect(tester.testTextInput.isVisible, isTrue);
  await tester.enterText(editor, value);
  if (cancel) {
    tester.testTextInput.hide();
    await tester.binding.handlePopRoute();
  } else {
    final dialog =
        find.ancestor(of: editor, matching: find.byType(AlertDialog));
    await tester
        .tap(find.descendant(of: dialog, matching: find.byType(FilledButton)));
  }
  await tester.pumpAndSettle();
  expect(editor, findsNothing);
  expect(entry.hasPrimaryFocus, isTrue);
}

String _value(WidgetTester tester, String key) => tester
    .widget<TvTextEntry>(find.byKey(ValueKey(key)))
    .child
    .controller!
    .text;

Future<void> _reopen(WidgetTester tester) async {
  final origin = Focus.of(tester.element(find.text('自定义日期')));
  expect(origin.hasPrimaryFocus, isTrue);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('tv-date-range-dialog')), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform oldPaths;
  setUpAll(() async {
    oldPaths = PathProviderPlatform.instance;
    directory = await Directory.systemTemp.createTemp('tv_search_date_');
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = oldPaths;
    await directory.delete(recursive: true);
  });

  testWidgets(
      'real search date entry Down reaches next control after IME closes',
      (tester) async {
    await _open(tester);
    // Exercise the former native input-mode path too, so a regression back to
    // that picker demonstrates the swallowed direction key rather than a key mismatch.
    if (find.byType(DateRangePickerDialog).evaluate().isNotEmpty) {
      final context = tester.element(find.byType(DateRangePickerDialog));
      await tester.tap(find.byTooltip(
          MaterialLocalizations.of(context).inputDateModeButtonLabel));
      await tester.pumpAndSettle();
      final nativeInput = find
          .descendant(
              of: find.byType(DateRangePickerDialog),
              matching: find.byType(EditableText))
          .first;
      tester.widget<EditableText>(nativeInput).focusNode.requestFocus();
      await tester.pumpAndSettle();
      tester.testTextInput.hide();
    }
    final before = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, isNot(same(before)),
        reason:
            'Down must leave the date navigation entry, not edit the caret');
    expect(_entryFocus(tester, 'tv-date-end').hasPrimaryFocus, isTrue);
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('both date editors cancel independently and navigate to actions',
      (tester) async {
    await _open(tester);
    expect(tester.testTextInput.isVisible, isFalse);
    for (final key in ['tv-date-start', 'tv-date-end']) {
      await _edit(tester, key, '2024-02-29', cancel: true);
      expect(_value(tester, key), '');
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_entryFocus(tester, 'tv-date-end').hasPrimaryFocus, isFalse);
    final actionFocus = FocusManager.instance.primaryFocus!;
    expect(
        actionFocus.context!.findAncestorWidgetOfExactType<TextButton>() !=
                null ||
            actionFocus.context!
                    .findAncestorWidgetOfExactType<FilledButton>() !=
                null,
        isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(_entryFocus(tester, 'tv-date-end').hasPrimaryFocus, isTrue);
    await tester.tap(find.byKey(const ValueKey('tv-date-cancel')));
    await tester.pumpAndSettle();
    await _reopen(tester);
    expect(_value(tester, 'tv-date-start'), '');
    expect(_value(tester, 'tv-date-end'), '');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'valid leap-day range roundtrips; cancelled replacement keeps draft',
      (tester) async {
    await _open(tester);
    await _edit(tester, 'tv-date-start', '2024-02-29');
    await _edit(tester, 'tv-date-end', '2024-03-01');
    await tester.tap(find.byKey(const ValueKey('tv-date-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tv-date-range-dialog')), findsNothing);
    await _reopen(tester);
    expect(_value(tester, 'tv-date-start'), '2024-02-29');
    expect(_value(tester, 'tv-date-end'), '2024-03-01');
    await _edit(tester, 'tv-date-start', '2020-01-01');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await _reopen(tester);
    expect(_value(tester, 'tv-date-start'), '2024-02-29');
    expect(_value(tester, 'tv-date-end'), '2024-03-01');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('malformed overflow and out-of-range dates stay open with errors',
      (tester) async {
    await _open(tester);
    await _edit(tester, 'tv-date-end', '2024-12-31');
    for (final bad in [
      '',
      '2024-2-29',
      ' 2024-02-29',
      '2023-02-29',
      '2024-02-30',
      '2024-13-01',
      '2024-01-00',
      '1969-12-31',
      '${DateTime.now().year + 4}-01-01'
    ]) {
      await _edit(tester, 'tv-date-start', bad);
      await tester.tap(find.byKey(const ValueKey('tv-date-confirm')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('tv-date-range-dialog')), findsOneWidget);
      expect(
          tester
              .widget<TvTextEntry>(find.byKey(const ValueKey('tv-date-start')))
              .child
              .decoration!
              .errorText,
          isNotNull,
          reason: bad);
      expect(_entryFocus(tester, 'tv-date-start').hasPrimaryFocus, isTrue);
    }
    await _edit(tester, 'tv-date-start', '2024-03-01');
    await _edit(tester, 'tv-date-end', '2024-02-29');
    await tester.tap(find.byKey(const ValueKey('tv-date-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('结束日期不能早于开始日期'), findsOneWidget);
    expect(_entryFocus(tester, 'tv-date-end').hasPrimaryFocus, isTrue);
    await _edit(tester, 'tv-date-start', '1970-01-01');
    await _edit(tester, 'tv-date-end', '${DateTime.now().year + 3}-12-31');
    await tester.tap(find.byKey(const ValueKey('tv-date-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tv-date-range-dialog')), findsNothing);
    await _reopen(tester);
    expect(_value(tester, 'tv-date-start'), '1970-01-01');
    expect(_value(tester, 'tv-date-end'), '${DateTime.now().year + 3}-12-31');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('non-TV search still opens native date range picker',
      (tester) async {
    await _open(tester, tv: false);
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    expect(find.byKey(const ValueKey('tv-date-range-dialog')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
