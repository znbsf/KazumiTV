import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/tv_visuals.dart';
import 'package:kazumi/pages/player/tv_player_controls.dart';

void main() {
  testWidgets('remote progress seeks within bounds and returns to actions',
      (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final seeks = <Duration>[];
    var actionsEntered = 0;

    Future<void> showProgress(Duration position, Duration duration) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TvPlayerProgress(
            focusNode: focus,
            position: position,
            duration: duration,
            buffered: Duration.zero,
            onSeek: seeks.add,
            onVerticalKey: () => actionsEntered++,
          ),
        ),
      ));
      focus.requestFocus();
      await tester.pump();
    }

    await showProgress(const Duration(seconds: 2), const Duration(seconds: 7));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(seeks, [Duration.zero, const Duration(seconds: 7)]);
    expect(actionsEntered, 1);

    await showProgress(Duration.zero, Duration.zero);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(seeks, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('player action remains visible and green when remotely focused',
      (tester) async {
    final farFocus = FocusNode();
    addTearDown(farFocus.dispose);
    var activations = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomLeft,
          child: SizedBox(
            width: 260,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (var index = 0; index < 12; index++)
                  TvPlayerAction(
                    label: '操作 $index',
                    focusNode: index == 11 ? farFocus : null,
                    onPressed: () => activations++,
                  ),
              ]),
            ),
          ),
        ),
      ),
    ));
    farFocus.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(activations, 1);
    expect(tester.getRect(find.text('操作 11')).right, lessThanOrEqualTo(260));
    final text = tester.widget<Text>(find.text('操作 11'));
    expect(text.style?.color, TvVisuals.accent);
    expect(text.style?.fontSize, 14);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings use a full height right panel and consume Back',
      (tester) async {
    var backs = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TvPlayerSettingsPanel(
          title: '设置',
          onBack: () => backs++,
          children: [
            TvPlayerAction(label: '播放速度', onPressed: () {}),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final panel = tester.getRect(find.byType(TvPlayerSettingsPanel));
    final background = tester.getRect(find.byType(ColoredBox).last);
    expect(background.width, 340);
    expect(background.right, panel.right);
    expect(background.height, panel.height);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(backs, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('icon actions retain remote activation, semantics and tooltip',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var activations = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomLeft,
          child: TvPlayerAction(
            label: '下一集',
            focusNode: focus,
            iconBuilder: (color) => Icon(
              Icons.skip_next_rounded,
              size: 24,
              color: color,
            ),
            onPressed: () => activations++,
          ),
        ),
      ),
    ));
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(find.text('下一集'), findsNothing);
    expect(find.bySemanticsLabel('下一集'), findsOneWidget);
    expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, '下一集');
    final icon = tester.widget<Icon>(find.byIcon(Icons.skip_next_rounded));
    expect(icon.color, TvVisuals.accent);
    expect(tester.getSize(find.byType(TvPlayerAction)), const Size(38, 38));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    expect(activations, 2);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
