import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/tv_visuals.dart';
import 'package:kazumi/pages/player/tv_player_controls.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('focus/selected/disabled remain distinct in $brightness',
        (tester) async {
      final node = FocusNode();
      var presses = 0;
      final base =
          ThemeData(colorSchemeSeed: Colors.green, brightness: brightness);
      await tester.pumpWidget(MaterialApp(
          theme: TvVisuals.theme(base),
          home: Scaffold(
              body: Column(children: [
            TvPlayerAction(
                label: 'enabled', focusNode: node, onPressed: () => presses++),
            TvPlayerAction(label: 'selected', selected: true, onPressed: () {}),
            const TvPlayerAction(label: 'disabled', onPressed: null),
          ]))));
      node.requestFocus();
      await tester.pumpAndSettle();
      Material material(String label) =>
          tester.widget<Material>(find.descendant(
              of: find.ancestor(
                  of: find.text(label), matching: find.byType(TvPlayerAction)),
              matching: find.byType(Material)));
      expect(material('enabled').color, base.colorScheme.primary);
      expect(
          (material('enabled').shape! as RoundedRectangleBorder).side.width, 3);
      expect(material('selected').color, base.colorScheme.secondaryContainer);
      expect(material('disabled').color, isNot(base.colorScheme.primary));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      expect(presses, 1);
      await tester.tap(find.text('disabled'));
      expect(presses, 1);
      await tester.pumpWidget(const SizedBox());
      node.dispose();
    });
  }
}
