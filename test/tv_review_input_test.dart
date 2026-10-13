import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/tv_text_entry.dart';
import 'package:kazumi/bean/widget/tv_focusable_surface.dart';
import 'package:kazumi/pages/info/rating_review_dialog.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'support/tv_focus_fixtures.dart';

void main() {
  testWidgets('review directional navigation never enters the shortcut shell',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    addTearDown(() => TvMode.setEnabledForTesting(false));
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var submissions = 0;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    autofocus: true,
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => RatingReviewDialog(
                            bangumiItem: focusItem(1),
                            onSubmit: (_) async {
                              submissions++;
                              return true;
                            })),
                    child: const Text('open'))))));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final close = Focus.of(tester.element(find.byIcon(Icons.close_rounded)));
    close.requestFocus();
    await tester.pumpAndSettle();
    final shell = find.byWidgetPredicate(
        (widget) => widget is Focus && (widget.child is Dialog));
    expect(shell, findsOneWidget);
    final shellNode = Focus.of(tester.element(find.byType(Dialog)));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(shellNode.hasPrimaryFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(shellNode.hasPrimaryFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(RatingReviewDialog), findsNothing);
    expect(submissions, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'review fields use nested edit route without submitting or closing review',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    addTearDown(() => TvMode.setEnabledForTesting(false));
    tester.view.physicalSize = const Size(960, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var submissions = 0;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => RatingReviewDialog(
                            bangumiItem: focusItem(1),
                            onSubmit: (_) async {
                              submissions++;
                              return true;
                            })),
                    child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final entry = find.byType(TvTextEntry).first;
    final focus = tester
        .widget<TvFocusableSurface>(find.descendant(
            of: entry, matching: find.byType(TvFocusableSurface)))
        .focusNode!;
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, false);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('tv-text-editor')), 'cancel this');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(RatingReviewDialog), findsOneWidget);
    expect(focus.hasFocus, true);
    expect(tester.widget<TvTextEntry>(entry).child.controller!.text, '');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('tv-text-editor')), 'first line\nsecond line');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(tester.widget<TvTextEntry>(entry).child.controller!.text,
        'first line\nsecond line');
    expect(submissions, 0);
    expect(find.byType(RatingReviewDialog), findsOneWidget);
    expect(focus.hasFocus, true);
    await tester.tap(find.widgetWithText(ActionChip, '自定义标签'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, false);
    final tagEntry = find.byType(TvTextEntry).last;
    final tagFocus = tester
        .widget<TvFocusableSurface>(find.descendant(
            of: tagEntry, matching: find.byType(TvFocusableSurface)))
        .focusNode!;
    tagFocus.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tv-text-editor')), 'tag');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'tag'), findsOneWidget);
    expect(tagFocus.hasFocus, true);
    expect(submissions, 0);
    expect(tester.takeException(), isNull);
  });
}
