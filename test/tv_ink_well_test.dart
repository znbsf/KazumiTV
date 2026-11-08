import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/connected_tabs.dart';
import 'package:kazumi/bean/widget/split_list_row.dart';
import 'package:kazumi/bean/widget/tv_ink_well.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

void main() {
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() => TvMode.setEnabledForTesting(false));

  for (final scale in [1.0, 1.5]) {
    testWidgets('row and tab focus outlines preserve size at text scale $scale',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Column(children: [
              SplitListRow(
                onTap: () {},
                child: const SizedBox(height: 60, child: Text('Row')),
              ),
              const DefaultTabController(
                length: 2,
                child: ConnectedTabs(labels: ['First', 'Second']),
              ),
            ]),
          ),
        ),
      ));
      final row = find.ancestor(
          of: find.text('Row'), matching: find.byType(TvInkWell));
      final tab = find.ancestor(
          of: find.text('First'), matching: find.byType(TvInkWell));
      final rowSize = tester.getSize(row);
      final tabSize = tester.getSize(tab);
      final primary = Theme.of(tester.element(row)).colorScheme.primary;

      BorderSide border(Finder surface) {
        final box = tester.widget<DecoratedBox>(find.descendant(
          of: surface,
          matching: find.byWidgetPredicate((widget) =>
              widget is DecoratedBox &&
              widget.position == DecorationPosition.foreground),
        ).first);
        return (box.decoration as BoxDecoration).border!.top;
      }

      Focus.of(tester.element(find.text('Row'))).requestFocus();
      await tester.pumpAndSettle();
      expect(Focus.of(tester.element(find.text('Row'))).hasPrimaryFocus, isTrue);
      expect(border(row).color, primary);
      expect(border(row).width, 3);
      expect(border(tab).color, Colors.transparent);
      expect(tester.getSize(row), rowSize);
      expect(tester.getSize(tab), tabSize);

      Focus.of(tester.element(find.text('First'))).requestFocus();
      // Focus notifications schedule the outline rebuild for the next frame.
      await tester.pumpAndSettle();
      expect(Focus.of(tester.element(find.text('First'))).hasPrimaryFocus, isTrue);
      expect(border(row).color, Colors.transparent);
      expect(border(tab).color, primary);
      expect(border(tab).width, 3);
      expect(tester.getSize(row), rowSize);
      expect(tester.getSize(tab), tabSize);
    });
  }

  testWidgets('focus background preserves the child state across focus changes',
      (tester) async {
    final focus = FocusNode();
    final other = FocusNode();
    const childKey = ValueKey('stateful-focus-child');
    addTearDown(focus.dispose);
    addTearDown(other.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          TvInkWell(
            focusNode: focus,
            focusBackground: true,
            onTap: () {},
            child: StatefulBuilder(
                key: childKey,
                builder: (_, __) => const Text('Stateful child')),
          ),
          TvInkWell(
            focusNode: other,
            onTap: () {},
            child: const Text('Other'),
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    final childState = tester.state(find.byKey(childKey));
    final childSize = tester.getSize(find.byKey(childKey));
    for (final target in [other, focus, other, focus]) {
      target.requestFocus();
      await tester.pumpAndSettle();
      expect(target.hasPrimaryFocus, isTrue);
      expect(tester.state(find.byKey(childKey)), same(childState));
      expect(tester.getSize(find.byKey(childKey)), childSize);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mobile ink well has no TV foreground decoration', (tester) async {
    TvMode.setEnabledForTesting(false);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SplitListRow(onTap: () {}, child: const Text('Row'))),
    ));
    expect(
      find.descendant(
        of: find.byType(TvInkWell),
        matching: find.byWidgetPredicate((widget) =>
            widget is DecoratedBox &&
            widget.position == DecorationPosition.foreground),
      ),
      findsNothing,
    );
  });
}
