import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

void main() {
  for (final size in [const Size(640, 360), const Size(1280, 800)]) {
    for (final up in [true, false]) {
      testWidgets('whole slider tile visible ${up ? 'up' : 'down'} $size',
          (tester) async {
        TvMode.setEnabledForTesting(true);
        addTearDown(() => TvMode.setEnabledForTesting(false));
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final scroll = ScrollController(), entry = FocusNode();
        addTearDown(scroll.dispose);
        addTearDown(entry.dispose);
        const viewport = ValueKey('viewport'), tile = ValueKey('tile');
        final changes = <double>[];
        Widget button() => TextButton(
            focusNode: entry, onPressed: () {}, child: const Text('Entry'));
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                appBar: AppBar(title: const Text('Fixed title')),
                body: SizedBox(
                    key: viewport,
                    height: size.height - 100,
                    child: SingleChildScrollView(
                        controller: scroll,
                        child: Column(children: [
                          if (!up) button(),
                          const SizedBox(height: 800),
                          SettingsSliderTile(
                              key: tile,
                              title: const Text('Setting label'),
                              description: const Text('Explanation'),
                              value: .5,
                              valueLabel: '50%',
                              min: 0,
                              max: 1,
                              divisions: 10,
                              onChanged: changes.add),
                          const SizedBox(height: 800),
                          if (up) button(),
                        ]))))));
        await tester.pumpAndSettle();
        scroll.jumpTo(up ? scroll.position.maxScrollExtent : 0);
        entry.requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(
            up ? LogicalKeyboardKey.arrowUp : LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        final bounds = tester.getRect(find.byKey(tile)),
            visible = tester.getRect(find.byKey(viewport));
        expect(entry.hasPrimaryFocus, isFalse);
        expect(bounds.top, greaterThanOrEqualTo(visible.top));
        expect(bounds.bottom, lessThanOrEqualTo(visible.bottom));
        expect(changes, isEmpty);
        final offset = scroll.offset;
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(changes.single, closeTo(.6, .0001));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(changes.last, closeTo(.4, .0001));
        expect(changes.length, 2);
        expect(scroll.offset, offset,
            reason:
                'value adjustment must not recenter an already visible tile');
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  testWidgets(
      'zero-range slider stays unfocusable and reveal wrapper is not a stop',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    addTearDown(() => TvMode.setEnabledForTesting(false));
    final before = FocusNode(), after = FocusNode();
    addTearDown(before.dispose);
    addTearDown(after.dispose);
    var changes = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      TextButton(
          focusNode: before, onPressed: () {}, child: const Text('Before')),
      SettingsSliderTile(
          title: const Text('Disabled'),
          value: 0,
          valueLabel: '0',
          min: 0,
          max: 0,
          onChanged: (_) => changes++),
      TextButton(
          focusNode: after, onPressed: () {}, child: const Text('After')),
    ]))));
    before.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(after.hasPrimaryFocus, isTrue);
    expect(changes, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
