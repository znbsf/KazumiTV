import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

import 'support/tv_focus_fixtures.dart';

void main() {
  tearDown(() => TvMode.setEnabledForTesting(false));

  testWidgets('Home poster pointer and focused select each activate once',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var openings = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 200,
            height: 320,
            child: BangumiCardV(
              bangumiItem: focusItem(2),
              posterOverlay: true,
              enableHero: false,
              focusNode: focus,
              onPressed: () => openings++,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(focus.hasPrimaryFocus, isTrue);

    // Exercise the actual image hit region, not the widget's callback directly.
    await tester.tapAt(tester.getCenter(find.byType(NetworkImgLayer)));
    await tester.pumpAndSettle();
    expect(openings, 1);
    expect(focus.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(openings, 2);
    expect(focus.hasPrimaryFocus, isTrue);
    expect(tester.takeException(), isNull);
  });
}
