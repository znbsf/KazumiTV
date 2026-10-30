import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/bounded_log_buffer.dart';
import 'package:kazumi/bean/widget/tv_focusable_surface.dart';
import 'package:kazumi/pages/player/episode_comments_view.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/modules/comments/comment_item.dart';

void main() {
  testWidgets('real discussion tab is reachable from its toolbar by remote',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    addTearDown(() => TvMode.setEnabledForTesting(false));
    await tester.pumpWidget(MaterialApp(
        home: DefaultTabController(
      length: 2,
      child: Scaffold(
          body: SizedBox(
              width: 400,
              height: 500,
              child: Column(children: [
                const TabBar(tabs: [Tab(text: '选集'), Tab(text: '讨论')]),
                Expanded(
                    child: TabBarView(children: [
                  const Text('Episodes'),
                  EpisodeCommentsView(
                    episode: 1,
                    episodeInfo: null,
                    comments: List.generate(
                        20,
                        (i) => EpisodeCommentItem.fromJson({
                              'user': {
                                'avatar': <String, dynamic>{},
                                'nickname': 'Reader'
                              },
                              'content': 'Long discussion $i\n' * 5,
                              'replies': [],
                            })),
                    isLoading: false,
                    hasError: false,
                    isAscending: true,
                    onToggleSort: () {},
                    onSelectEpisode: () {},
                    onRefresh: () {},
                  ),
                ])),
              ]))),
    )));
    await tester.tap(find.text('讨论'));
    await tester.pumpAndSettle();
    final scrollable = find.descendant(
        of: find.byType(EpisodeCommentsView),
        matching: find.byType(Scrollable));
    final position = tester.state<ScrollableState>(scrollable).position;
    for (var i = 0; i < 8; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(position.pixels, greaterThan(300));
    final before = position.pixels;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(position.pixels, lessThan(before));
    expect(tester.takeException(), isNull);
  });

  testWidgets('discussion reader scrolls down, repeats, reverses and reopens',
      (tester) async {
    var outsideDown = 0;
    var backs = 0;
    Widget reader(int episode) => MaterialApp(
            home: Scaffold(
                body: Focus(
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) backs++;
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowDown) outsideDown++;
            return KeyEventResult.ignored;
          },
          child: SizedBox(
              width: 350,
              height: 300,
              child: DiscussionScrollRegion(
                key: ValueKey(episode),
                enabled: true,
                builder: (controller) => ListView.builder(
                    controller: controller,
                    itemCount: 60,
                    itemExtent: 100,
                    itemBuilder: (_, i) => Text('Discussion $i')),
              )),
        )));
    await tester.pumpWidget(reader(1));
    await tester.pumpAndSettle();
    ScrollPosition position() =>
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(position().pixels, 0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(position().pixels, greaterThan(300));
    final down = position().pixels;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(position().pixels, lessThan(down));
    expect(outsideDown, 0);
    position().jumpTo(position().maxScrollExtent);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(position().pixels, lessThan(position().maxScrollExtent));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(backs, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(reader(2));
    await tester.pumpAndSettle();
    expect(position().pixels, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(position().pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

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
