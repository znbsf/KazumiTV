import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/card/bangumi_timeline_card.dart';
import 'package:kazumi/bean/widget/tv_focusable_surface.dart';
import 'package:kazumi/bean/widget/tv_visuals.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

BangumiItem item(int id) => BangumiItem(
      id: id,
      type: 2,
      name: 'A long title',
      nameCn: '乱世千金倪亚·利斯顿转生为病弱千金的弑神武人华丽无双录',
      summary: '',
      airDate: '',
      airWeekday: 1,
      rank: 1,
      images: {},
      tags: [],
      alias: [],
      ratingScore: 7.8,
      votes: 1,
      votesCount: [],
      info: '12 话',
      metaTags: ['TV', '日本'],
    );

void main() {
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() => TvMode.setEnabledForTesting(false));

  for (final viewport in [const Size(960, 540), const Size(1280, 720)]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('TV timeline long title fits at $viewport text scale $scale',
          (tester) async {
        tester.view.physicalSize = viewport * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final scaler = TextScaler.linear(scale);
        await tester.pumpWidget(MaterialApp(
            theme: TvVisuals.theme(ThemeData.dark()),
            home: MediaQuery(
          data: MediaQueryData(size: viewport, textScaler: scaler),
          child: Scaffold(
              body: Padding(
            padding: const EdgeInsets.fromLTRB(24, 164, 24, 0),
            child: GridView.builder(
              itemCount: 8,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: BangumiTimelineCard.heightFor(scaler)),
              itemBuilder: (_, i) => BangumiTimelineCard(
                  key: ValueKey(i),
                  bangumiItem: item(i),
                  showRating: true,
                  isWatching: true,
                  onTap: () {}),
            ),
          )),
        )));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final label in ['12 话 · TV · 日本', '7.8']) {
          final text = find.descendant(
              of: find.byKey(const ValueKey(0)), matching: find.text(label));
          expect(tester.widget<Text>(text).style?.fontSize, 14);
        }
        if (scale == 1) {
          for (var i = 0; i < 6; i++) {
            expect(tester.getRect(find.byKey(ValueKey(i))).bottom,
                lessThanOrEqualTo(viewport.height),
                reason: 'three complete rows');
          }
          final first = find
              .descendant(
                  of: find.byKey(const ValueKey(0)), matching: find.byType(Focus))
              .first;
          final focus = tester.widget<Focus>(first);
          // Use the actual surface focus node, then move across and down.
          Focus.of(tester.element(find.byType(Card).first)).requestFocus();
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
          final surfaces = tester
              .widgetList<TvFocusableSurface>(find.byType(TvFocusableSurface));
          expect(surfaces.every((s) => s.focusScale == 1), isTrue);
          expect(focus.descendantsAreFocusable, isFalse);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
