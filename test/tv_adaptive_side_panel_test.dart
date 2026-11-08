import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:kazumi/bean/widget/tv_player_side_panel.dart';
import 'package:kazumi/pages/player/tv_player_focus.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

void main() {
  tearDown(() => TvMode.setEnabledForTesting(false));

  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('TV panel fills right edge at $size / $scale; Back restores focus',
          (tester) async {
        TvMode.setEnabledForTesting(true);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final opener = FocusNode(), first = FocusNode(), second = FocusNode();
        addTearDown(opener.dispose);
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        final reclaimed = <bool>[];
        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          home: Builder(builder: (context) => Scaffold(
            body: TextButton(
              focusNode: opener,
              onPressed: () {
                Timer(const Duration(seconds: 3), () {
                  reclaimed.add(requestPlayerFocusIfCurrent(context, opener));
                });
                showAdaptiveBottomSheet<void>(
                  context: context,
                  // These deliberately tiny caps must have no effect on TV.
                  maxHeightFactor: .1,
                  compactLandscapeMaxHeightFactor: .1,
                  builder: (_) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(focusNode: first, onPressed: () {},
                          child: const Text('First')),
                      TextButton(focusNode: second, onPressed: () {},
                          child: const Text('Second')),
                    ],
                  ),
                );
              },
              child: const Text('Open'),
            ),
          )),
        ));
        opener.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        final panel = find.byType(TvPlayerSidePanel);
        final rect = tester.getRect(panel);
        expect(rect.right, size.width);
        expect(rect.top, 0);
        expect(rect.height, size.height);
        expect(rect.width, closeTo(size.width == 960 ? 403.2 : 440, .001));
        expect(tester.widget<TvPlayerSidePanel>(panel).opacity, 1);
        expect(find.byType(BottomSheet), findsNothing);
        expect(first.hasPrimaryFocus, isTrue);
        // Short content is top aligned, rather than vertically centered.
        expect(tester.getRect(find.text('First')).top, lessThan(50));
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        expect(reclaimed, [false]);
        expect(first.hasPrimaryFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(second.hasPrimaryFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(panel, findsNothing);
        expect(opener.hasPrimaryFocus, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('TV respects autofocus, returns pop results and disables motion',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    final selected = FocusNode();
    addTearDown(selected.dispose);
    String? result;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Builder(builder: (context) => Scaffold(body: TextButton(
        onPressed: () async {
          result = await showAdaptiveBottomSheet<String>(
            context: context,
            builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
              TextButton(onPressed: () {}, child: const Text('First')),
              TextButton(
                autofocus: true,
                focusNode: selected,
                onPressed: () => Navigator.of(context).pop('done'),
                child: const Text('Selected'),
              ),
            ]),
          );
        },
        child: const Text('Open'),
      ))),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(selected.hasPrimaryFocus, isTrue);
    final route = ModalRoute.of(tester.element(find.text('Selected')))!;
    expect(route.transitionDuration, Duration.zero);
    expect(route.animation!.value, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result, 'done');
    expect(find.byType(TvPlayerSidePanel), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('non-TV still uses a capped bottom sheet', (tester) async {
    TvMode.setEnabledForTesting(false);
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Builder(
      builder: (context) => Scaffold(body: TextButton(
        onPressed: () => showAdaptiveBottomSheet<void>(
          context: context,
          builder: (_) => const SizedBox(height: 150, child: Text('Content')),
        ),
        child: const Text('Open'),
      )),
    )));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(TvPlayerSidePanel), findsNothing);
    final rect = tester.getRect(find.text('Content'));
    expect(rect.width, closeTo(640, 0.01));
    expect(rect.bottom, closeTo(540, 0.01));
    expect(rect.height, closeTo(150, 0.01));
    expect(rect.left, closeTo(160, 0.01));
    expect(tester.takeException(), isNull);
  });
}
