import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/tv_range_slider.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

void main() {
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() => TvMode.setEnabledForTesting(false));
  for (final rank in [false, true]) {
    testWidgets(
        'TV ${rank ? "rank" : "score"} endpoints adjust, clamp and escape',
        (tester) async {
      final min = rank ? 1.0 : 0.0, max = rank ? 10000.0 : 10.0;
      final divisions = rank ? 100 : 20;
      final step = (max - min) / divisions;
      var values = RangeValues(min, max);
      final before = FocusNode(), after = FocusNode();
      addTearDown(before.dispose);
      addTearDown(after.dispose);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: StatefulBuilder(
                  builder: (context, setState) => Column(children: [
                        TextButton(
                            focusNode: before,
                            onPressed: () {},
                            child: const Text('Before')),
                        TvRangeSlider(
                            child: RangeSlider(
                                values: values,
                                min: min,
                                max: max,
                                divisions: divisions,
                                onChanged: (v) => setState(() => values = v))),
                        TextButton(
                            focusNode: after,
                            onPressed: () {},
                            child: const Text('After')),
                      ])))));
      before.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(values.start, closeTo(min + step, .00001));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(values.end, closeTo(max - 2 * step, .00001));
      for (var i = 0; i < divisions + 2; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
      }
      expect(values.end, closeTo(values.start, .00001));
      final saved = values;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(after.hasFocus, isTrue);
      expect(values, saved);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(before.hasFocus, isTrue);
      expect(values, saved);
    });
  }
  testWidgets('non-TV retains native RangeSlider touch behavior',
      (tester) async {
    TvMode.setEnabledForTesting(false);
    var values = const RangeValues(2, 8);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => TvRangeSlider(
                    child: RangeSlider(
                        values: values,
                        min: 0,
                        max: 10,
                        divisions: 20,
                        onChanged: (v) => setState(() => values = v)))))));
    expect(find.textContaining('下限'), findsNothing);
    await tester.dragFrom(
        tester.getCenter(find.byType(RangeSlider)) + const Offset(-220, 0),
        const Offset(100, 0));
    await tester.pumpAndSettle();
    expect(values, isNot(const RangeValues(2, 8)));
  });
}
