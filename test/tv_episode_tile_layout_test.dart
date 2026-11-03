import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/episode_tile.dart';
import 'package:kazumi/bean/widget/tv_focusable_surface.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

void main() {
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() => TvMode.setEnabledForTesting(false));

  for (final width in [360.0, 403.2, 440.0]) {
    for (final scale in [1.0, 1.25, 1.3, 1.5]) {
      testWidgets('real TV grid width $width, text $scale fits two-line titles',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(body: Builder(builder: (context) {
              return SizedBox(
                width: width,
                child: GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 3,
                    mainAxisExtent: EpisodeTile.tvGridMainAxisExtent(context),
                  ),
                  itemCount: 12,
                  itemBuilder: (context, i) => Container(
                    margin: const EdgeInsets.only(bottom: 2),
                    child: EpisodeTile(
                        label: '本地第 ${i + 1} 集 长标题',
                        isPlaying: i == 1,
                        onPressed: () {},
                        status: const Icon(Icons.offline_pin, size: 12)),
                  ),
                ),
              );
            })),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
        final text = tester.widget<Text>(find.descendant(
            of: find.byType(TvFocusableSurface),
            matching: find.text('本地第 2 集 长标题')));
        expect(text.maxLines, 2);
        expect(text.overflow, TextOverflow.ellipsis);
        expect(text.style?.fontSize, 14);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('phone episode title keeps its original size and focus behavior',
      (tester) async {
    TvMode.setEnabledForTesting(false);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EpisodeTile(
                label: '手机集名', isPlaying: true, onPressed: () {}))));
    Focus.of(tester.element(find.text('手机集名'))).requestFocus();
    await tester.pumpAndSettle();
    expect(find.text('手机集名'), findsOneWidget);
    final text = tester.widget<Text>(find.text('手机集名'));
    expect(text.style?.fontSize, 13);
    expect(text.style?.height, isNull);
    expect(find.byType(OverlayPortal), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
