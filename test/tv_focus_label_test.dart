import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/tv_focus_label.dart';
import 'package:kazumi/bean/widget/tv_focusable_surface.dart';
import 'package:kazumi/pages/player/tv_player_controls.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

void main() {
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() => TvMode.setEnabledForTesting(false));

  testWidgets('X2 player name appears only on TV focus without layout change',
      (tester) async {
    final node = FocusNode();
    final other = FocusNode();
    addTearDown(node.dispose);
    addTearDown(other.dispose);
    var presses = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Row(children: [
      TvPlayerAction(
        label: '下一集',
        focusNode: node,
        onPressed: () => presses++,
        iconBuilder: (color) => Icon(Icons.skip_next, color: color),
      ),
      TextButton(
          focusNode: other, onPressed: () {}, child: const Text('other')),
    ]))));
    final before = tester.getRect(find.byType(TvPlayerAction));
    expect(find.text('下一集'), findsNothing);
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(find.text('下一集'), findsOneWidget);
    expect(tester.getRect(find.byType(TvPlayerAction)), before);
    expect(node.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(presses, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(other.hasPrimaryFocus, isTrue);
    expect(find.text('下一集'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  for (final alignment in [
    Alignment.topLeft,
    Alignment.topRight,
    Alignment.bottomLeft,
    Alignment.bottomRight
  ]) {
    testWidgets('X2 label stays inside viewport at $alignment with large text',
        (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      const label = '原生选集实验：关闭（点击开启）';
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
        data: const MediaQueryData(
            size: Size(800, 600),
            padding: EdgeInsets.all(12),
            textScaler: TextScaler.linear(2)),
        child: Scaffold(
            body: Align(
          alignment: alignment,
          child: TvFocusLabel(
              message: label,
              child: IconButton(
                  focusNode: node,
                  tooltip: label,
                  onPressed: () {},
                  icon: const Icon(Icons.settings))),
        )),
      )));
      node.requestFocus();
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.text(label));
      expect(rect.left, greaterThanOrEqualTo(20));
      expect(rect.top, greaterThanOrEqualTo(20));
      expect(rect.right, lessThanOrEqualTo(780));
      expect(rect.bottom, lessThanOrEqualTo(580));
      expect(node.hasPrimaryFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(find.text(label), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'X2 label observes the outer history surface and cannot intercept taps',
      (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    var presses = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
      child: TvFocusLabel(
          message: '更多历史操作',
          child: TvFocusableSurface(
            focusNode: node,
            onPressed: () => presses++,
            child: IconButton(
                tooltip: '更多历史操作',
                onPressed: () => presses++,
                icon: const Icon(Icons.more_horiz)),
          )),
    ))));
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(find.text('更多历史操作'), findsOneWidget);
    final ignore = find
        .ancestor(of: find.text('更多历史操作'), matching: find.byType(IgnorePointer))
        .first;
    expect(tester.widget<IgnorePointer>(ignore).ignoring, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(presses, 1);
    expect(node.hasPrimaryFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('X2 phone focus keeps the original icon and tooltip only',
      (tester) async {
    TvMode.setEnabledForTesting(false);
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: TvFocusLabel(
          message: '搜索',
          child: IconButton(
              focusNode: node,
              tooltip: '搜索',
              onPressed: () {},
              icon: const Icon(Icons.search))),
    )));
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(find.text('搜索'), findsNothing);
    expect(find.byTooltip('搜索'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
