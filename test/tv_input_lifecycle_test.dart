import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/tv_desktop_navigation.dart';
import 'package:kazumi/services/performance/tv_input_lifecycle.dart';

void main() {
  testWidgets('observes full held key without handling it or creating frames',
      (tester) async {
    var clock = 0;
    final node = FocusNode();
    addTearDown(node.dispose);
    TvDesktopNavigation.registerHomeFocus(node,
        const TvHomeFocusIdentity.poster(subjectId: 41, channelNumber: 1));
    final handled = <KeyEvent>[];
    await tester.pumpWidget(MaterialApp(
        home: Focus(
            focusNode: node,
            onKeyEvent: (_, event) {
              TvInputLifecycle.trace('business_handler', {}, inputEvent: event);
              handled.add(event);
              return KeyEventResult.handled;
            },
            child: const Text('card'))));
    node.requestFocus();
    await tester.pump();
    final lifecycle = TvInputLifecycle(() => clock)..install();
    addTearDown(lifecycle.dispose);
    final release = TvInputLifecycle.registerPageState(Object(),
        isCurrent: () => true,
        read: () => {
              'route': '/tab/popular/',
              'scrollOffset': 0.0,
              'scrollTraceEnabled': true
            },
        readCatalogIds: () => [41, 42]);
    addTearDown(release);
    lifecycle.start(0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    clock = 450000;
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    clock = 630000;
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    clock = 2130000;
    lifecycle.stop();
    final report = lifecycle.report();
    final events = report['appEvents'] as List;
    expect(events.map((e) => e['type']), ['down', 'repeat', 'up']);
    expect(events.map((e) => e['itemId']), [41, 41, 41]);
    expect(events.map((e) => e['inputSource']),
        List.filled(3, 'HardwareKeyboard.before_focus_routing'));
    expect((report['gridEvents'] as List).take(3).map((e) => e['inputSeq']),
        [1, 2, 3],
        reason:
            'The actual business handler must see the pre-routing sequence.');
    expect(handled, hasLength(5));
    expect((report['logging'] as Map)['appComplete'], isTrue);
    expect((report['logging'] as Map)['scrollComplete'], isTrue);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('release after window closes cannot disguise a missing KeyUp',
      (tester) async {
    final lifecycle = TvInputLifecycle(() => 0)..install();
    addTearDown(lifecycle.dispose);
    lifecycle.start(0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    lifecycle.stop();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    expect((lifecycle.report()['logging'] as Map)['appComplete'], isFalse);
    expect(lifecycle.report()['pressedAtEnd'], isNotEmpty);
  });

  testWidgets('bounds and stale page leases never report complete evidence',
      (tester) async {
    final lifecycle = TvInputLifecycle(() => 0)..install();
    addTearDown(lifecycle.dispose);
    final owner = Object();
    final stale = TvInputLifecycle.registerPageState(owner,
        isCurrent: () => true,
        read: () => {'route': 'old'},
        readCatalogIds: () => []);
    final latest = TvInputLifecycle.registerPageState(owner,
        isCurrent: () => true,
        read: () => {'route': 'new'},
        readCatalogIds: () => []);
    addTearDown(latest);
    stale();
    lifecycle.start(0);
    for (var i = 0; i < 513; i++) {
      TvInputLifecycle.trace('request', {'index': i});
    }
    lifecycle.stop();
    final report = lifecycle.report();
    expect((report['catalogStart'] as Map)['route'], 'new');
    expect(report['gridEvents'], hasLength(512));
    expect((report['logging'] as Map)['dropped'], 1);
    expect((report['logging'] as Map)['appComplete'], isFalse);
    expect((report['logging'] as Map)['scrollComplete'], isFalse);
  });

  testWidgets('leaving a registered page revokes whole-window scroll coverage',
      (tester) async {
    final life = TvInputLifecycle(() => 0)..install();
    addTearDown(life.dispose);
    var current = true;
    final release = TvInputLifecycle.registerPageState(Object(),
        isCurrent: () => current,
        read: () =>
            {'route': 'home', 'scrollOffset': 0, 'scrollTraceEnabled': true},
        readCatalogIds: () => [1]);
    addTearDown(release);
    life.start(0);
    current = false;
    TvInputLifecycle.checkpoint('covered');
    current = true;
    life.stop();
    expect((life.report()['logging'] as Map)['scrollComplete'], isFalse);
    expect((life.report()['catalogEnd'] as Map)['ids'], [1]);
  });
}
