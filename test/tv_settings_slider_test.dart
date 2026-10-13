import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/bean/widget/tv_slider_navigation.dart';
import 'package:kazumi/pages/player/player_adjustment_hud.dart';

void main() {
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() => TvMode.setEnabledForTesting(false));
  testWidgets(
      'issue 3 default-speed vertical keys leave slider without changing value',
      (tester) async {
    var value = 1.0;
    final above = FocusNode(), below = FocusNode();
    addTearDown(above.dispose);
    addTearDown(below.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => Column(children: [
                      TextButton(
                          focusNode: above,
                          onPressed: () {},
                          child: const Text('Above')),
                      SettingsSliderTile(
                          title: const Text('Default speed'),
                          value: value,
                          valueLabel: '$value',
                          min: .25,
                          max: 3,
                          divisions: 11,
                          onChanged: (v) => setState(() => value = v)),
                      TextButton(
                          focusNode: below,
                          onPressed: () {},
                          child: const Text('Below')),
                    ])))));
    above.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
        FocusManager.instance.primaryFocus!.context!
            .findAncestorWidgetOfExactType<Slider>(),
        isNotNull);
    final before = value;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(value, before,
        reason: 'vertical navigation must not adjust default speed');
    expect(below.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(above.hasFocus, isTrue);
    expect(value, before);
  });

  for (final visible in [false, true]) {
    testWidgets('display-only HUD cannot steal focus visible=$visible',
        (tester) async {
      final before = FocusNode(), after = FocusNode();
      addTearDown(before.dispose);
      addTearDown(after.dispose);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Column(children: [
        TextButton(
            focusNode: before, onPressed: () {}, child: const Text('Before')),
        PlayerAdjustmentHud(
            visible: visible,
            type: PlayerAdjustmentHudType.volume,
            value: 50,
            disableAnimations: true),
        TextButton(
            focusNode: after, onPressed: () {}, child: const Text('After')),
      ]))));
      before.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(after.hasFocus, isTrue);
    });
  }

  testWidgets('left/right repeat adjusts once; endpoints never leak to sidebar',
      (tester) async {
    var value = 1.0, changes = 0, parentArrows = 0;
    final slider = FocusNode();
    addTearDown(slider.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => Focus(
                      onKeyEvent: (_, e) {
                        if (e is KeyDownEvent || e is KeyRepeatEvent) {
                          parentArrows++;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TvSliderNavigation(
                          child: Slider(
                              focusNode: slider,
                              value: value,
                              min: 0,
                              max: 2,
                              divisions: 2,
                              onChanged: (v) => setState(() {
                                    value = v;
                                    changes++;
                                  }))),
                    )))));
    slider.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(value, 2);
    expect(changes, 1);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(value, 2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(value, 1);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(value, 0);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(value, 0);
    expect(parentArrows, 0);
    expect(slider.hasFocus, isTrue);
  });

  testWidgets(
      'up/down without a target consumes repeat and release without value changes',
      (tester) async {
    var value = .5, parentEvents = 0;
    final slider = FocusNode();
    addTearDown(slider.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Focus(
                onKeyEvent: (_, e) {
                  parentEvents++;
                  return KeyEventResult.ignored;
                },
                child: TvSliderNavigation(
                    child: Slider(
                        focusNode: slider,
                        value: value,
                        onChanged: (v) => value = v))))));
    slider.requestFocus();
    await tester.pumpAndSettle();
    for (final key in [
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown
    ]) {
      await tester.sendKeyDownEvent(key);
      await tester.pump();
      await tester.sendKeyRepeatEvent(key);
      await tester.pump();
      await tester.sendKeyUpEvent(key);
      await tester.pump();
    }
    expect(value, .5);
    expect(parentEvents, 0);
    expect(slider.hasFocus, isTrue);
  });

  testWidgets(
      'disabled slider skipped and touch drag still uses native callbacks',
      (tester) async {
    final before = FocusNode(), disabled = FocusNode(), after = FocusNode();
    addTearDown(before.dispose);
    addTearDown(disabled.dispose);
    addTearDown(after.dispose);
    var value = .5;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => Column(children: [
                      TextButton(
                          focusNode: before,
                          onPressed: () {},
                          child: const Text('Before')),
                      TvSliderNavigation(
                          child: Slider(
                              focusNode: disabled, value: .5, onChanged: null)),
                      TextButton(
                          focusNode: after,
                          onPressed: () {},
                          child: const Text('After')),
                      TvSliderNavigation(
                          child: Slider(
                              key: const ValueKey('touch'),
                              value: value,
                              onChanged: (v) => setState(() => value = v))),
                    ])))));
    before.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(after.hasFocus, isTrue);
    expect(disabled.hasFocus, isFalse);
    await tester.drag(
        find.byKey(const ValueKey('touch')), const Offset(180, 0));
    await tester.pumpAndSettle();
    expect(value, greaterThan(.5));
  });

  testWidgets('non-TV retains Material vertical adjustment', (tester) async {
    TvMode.setEnabledForTesting(false);
    var value = 1.0;
    final slider = FocusNode();
    addTearDown(slider.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => TvSliderNavigation(
                    child: Slider(
                        focusNode: slider,
                        value: value,
                        min: 0,
                        max: 2,
                        divisions: 2,
                        onChanged: (v) => setState(() => value = v)))))));
    slider.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(value, 2);
  });

  testWidgets('dialog slider down reaches close and restores opener focus',
      (tester) async {
    final opener = FocusNode(), slider = FocusNode(), close = FocusNode();
    addTearDown(opener.dispose);
    addTearDown(slider.dispose);
    addTearDown(close.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    focusNode: opener,
                    autofocus: true,
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                                content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                  TvSliderNavigation(
                                      child: Slider(
                                          focusNode: slider,
                                          autofocus: true,
                                          value: .5,
                                          onChanged: (_) {})),
                                  TextButton(
                                      focusNode: close,
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('Close')),
                                ]))),
                    child: const Text('Open'))))));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(slider.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(close.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opener.hasFocus, isTrue);
  });

  testWidgets(
      'scrolling vertical exit reveals destination and key-up does not move again',
      (tester) async {
    final scroll = ScrollController(),
        slider = FocusNode(),
        below = FocusNode();
    addTearDown(scroll.dispose);
    addTearDown(slider.dispose);
    addTearDown(below.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                height: 180,
                child: SingleChildScrollView(
                    controller: scroll,
                    child: Column(children: [
                      TvSliderNavigation(
                          child: Slider(
                              focusNode: slider, value: .5, onChanged: (_) {})),
                      const SizedBox(height: 300),
                      TextButton(
                          focusNode: below,
                          onPressed: () {},
                          child: const Text('Destination')),
                    ]))))));
    slider.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(below.hasFocus, isTrue);
    expect(scroll.offset, greaterThan(0));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(below.hasFocus, isTrue);
  });

  for (final step in [.25, .5, 1.0]) {
    testWidgets(
        'native step $step: down plus three repeats is four increments; release is inert',
        (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      var value = 0.0, changes = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: StatefulBuilder(
                  builder: (context, setState) => TvSliderNavigation(
                      child: Slider(
                          focusNode: node,
                          value: value,
                          min: 0,
                          max: step * 10,
                          divisions: 10,
                          onChanged: (v) => setState(() {
                                value = v;
                                changes++;
                              })))))));
      node.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      for (var n = 0; n < 3; n++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
      }
      expect(value, closeTo(step * 4, .000001));
      expect(changes, 4);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(changes, 4);
      expect(value, closeTo(step * 4, .000001));
    });
  }
}
