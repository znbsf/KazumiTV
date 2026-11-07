import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/bounded_log_buffer.dart';
import 'package:kazumi/bean/widget/tv_focusable_surface.dart';

void main() {
  testWidgets(
      'log updates rebuild only an open viewer and retain bounded history',
      (tester) async {
    final logs = BoundedLogBuffer();
    addTearDown(logs.dispose);
    var pageBuilds = 0;
    var viewerBuilds = 0;
    Widget page(bool visible) => MaterialApp(home: Builder(builder: (_) {
          pageBuilds++;
          return Visibility(
              visible: visible,
              child: ListenableBuilder(
                  listenable: logs,
                  builder: (context, child) {
                    viewerBuilds++;
                    return Text(logs.lines.join('\n'));
                  }));
        }));
    await tester.pumpWidget(page(false));
    for (var i = 0; i < 200; i++) {
      logs.add('line $i');
    }
    await tester.pump();
    expect(pageBuilds, 1);
    expect(viewerBuilds, 0);
    expect(logs.lines.length, 100);
    expect(logs.lines.first, 'line 100');
    await tester.pumpWidget(page(true));
    final before = pageBuilds;
    logs.add('latest');
    await tester.pump();
    expect(pageBuilds, before);
    expect(find.textContaining('latest'), findsOneWidget);
    logs.clear();
    await tester.pump();
    expect(logs.lines, isEmpty);
  });

  testWidgets('poster content is not repainted during focus scale animation',
      (tester) async {
    var paints = 0;
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: TvFocusableSurface(
      enabled: true,
      focusNode: node,
      onPressed: () {},
      child: CustomPaint(
          size: const Size(120, 180), painter: _CountPaint(() => paints++)),
    ))));
    final before = paints;
    node.requestFocus();
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(paints, before);
  });
}

class _CountPaint extends CustomPainter {
  _CountPaint(this.onPaint);
  final VoidCallback onPaint;
  @override
  void paint(Canvas canvas, Size size) {
    onPaint();
    canvas.drawRect(Offset.zero & size, Paint());
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
