import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/tv_focusable_surface.dart';

void main() {
  testWidgets('focus border switches on the first frame, before scale settles',
      (tester) async {
    final nodes = [FocusNode(), FocusNode()];
    addTearDown(() {
      for (final node in nodes) {
        node.dispose();
      }
    });
    await tester.pumpWidget(MaterialApp(
      home: Row(children: [
        for (var i = 0; i < nodes.length; i++)
          TvFocusableSurface(
            enabled: true,
            focusNode: nodes[i],
            autofocus: i == 0,
            onPressed: () {},
            child: const SizedBox(width: 120, height: 80),
          ),
      ]),
    ));
    await tester.pumpAndSettle();
    nodes[1].requestFocus();
    FocusManager.instance.applyFocusChangesIfNeeded();
    await tester.pump();
    final primary =
        Theme.of(tester.element(find.byType(Row))).colorScheme.primary;
    final surfaces = find.byType(TvFocusableSurface);
    BoxDecoration paintedBorder(int index) => tester
        .widget<DecoratedBox>(find.descendant(
            of: surfaces.at(index), matching: find.byType(DecoratedBox)))
        .decoration as BoxDecoration;
    expect((paintedBorder(0).border! as Border).top.color, Colors.transparent);
    expect((paintedBorder(1).border! as Border).top.color, primary);
    expect(paintedBorder(1).boxShadow!.single.blurRadius, 14);
    final scale = find.descendant(
        of: surfaces.at(1), matching: find.byType(ScaleTransition));
    expect(tester.widget<ScaleTransition>(scale).scale.value, 1);
    await tester.pump(const Duration(milliseconds: 90));
    expect(tester.widget<ScaleTransition>(scale).scale.value,
        closeTo(1.035, 0.001));
  });

  testWidgets('TV select key activates the focused surface', (tester) async {
    var activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFocusableSurface(
            enabled: true,
            autofocus: true,
            onPressed: () => activations += 1,
            child: const SizedBox(width: 120, height: 80),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(activations, 1);
  });

  testWidgets('disabled TV surface preserves the unwrapped mobile child',
      (tester) async {
    const childKey = Key('mobile-child');
    await tester.pumpWidget(
      MaterialApp(
        home: TvFocusableSurface(
          enabled: false,
          onPressed: () {},
          child: const SizedBox(key: childKey),
        ),
      ),
    );

    expect(find.byKey(childKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TvFocusableSurface),
        matching: find.byType(Focus),
      ),
      findsNothing,
    );
  });

  testWidgets('number selection can highlight a TV surface before focus',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFocusableSurface(
            enabled: true,
            highlighted: true,
            onPressed: () {},
            child: const SizedBox(width: 120, height: 80),
          ),
        ),
      ),
    );

    final decoration = tester.widget<Container>(
      find.descendant(
        of: find.byType(TvFocusableSurface),
        matching: find.byType(Container),
      ),
    );
    final box = decoration.decoration! as BoxDecoration;
    expect((box.border! as Border).top.color, isNot(Colors.transparent));
  });

  testWidgets('TV surface reports focus changes for horizontal category tabs',
      (tester) async {
    final changes = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFocusableSurface(
            enabled: true,
            autofocus: true,
            onFocusChange: changes.add,
            onPressed: () {},
            child: const SizedBox(width: 120, height: 80),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(changes, contains(true));
  });

  testWidgets('one D-pad step skips nested pointer focus targets',
      (tester) async {
    final firstFocus = FocusNode();
    final secondFocus = FocusNode();
    addTearDown(firstFocus.dispose);
    addTearDown(secondFocus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              TvFocusableSurface(
                enabled: true,
                autofocus: true,
                focusNode: firstFocus,
                onPressed: () {},
                child: InkWell(
                  onTap: () {},
                  child: const SizedBox(width: 120, height: 80),
                ),
              ),
              TvFocusableSurface(
                enabled: true,
                focusNode: secondFocus,
                onPressed: () {},
                child: InkWell(
                  onTap: () {},
                  child: const SizedBox(width: 120, height: 80),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(firstFocus.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(secondFocus.hasFocus, isTrue);
  });
}
