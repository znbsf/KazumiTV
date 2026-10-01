import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/video/episode_selection_panel.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

void main() {
  const channel = MethodChannel('com.predidit.kazumi/episode_browser');
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() {
    TvMode.setEnabledForTesting(false);
    messenger.setMockMethodCallHandler(channel, null);
  });
  Widget panel(void Function(int, int) select,
          {Future<void> Function()? opening}) =>
      MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 400,
                  height: 460,
                  child: EpisodeSelectionPanel(
                    title: '长篇',
                    selectedRoad: 0,
                    selectedEpisode: 1,
                    roads: [
                      Road(
                          name: '线路',
                          data: List.generate(
                              1000, (i) => 'https://private.invalid/$i'),
                          identifier: List.generate(1000, (i) => '第${i + 1}集'))
                    ],
                    downloads: const {},
                    onEpisodeSelected: select,
                    onNativeBrowserOpening: opening,
                  ))));

  testWidgets('Flutter fallback locates 999 without navigating 249 rows',
      (tester) async {
    final selected = <int>[];
    await tester.pumpWidget(panel((episode, _) => selected.add(episode)));
    await tester.tap(find.byKey(const ValueKey('episode-quick-browser')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('episode-jump-number')), '999');
    await tester.tap(find.text('定位'));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TV episode 0:999');
    expect(selected, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(selected, [999]);
    expect(tester.takeException(), isNull);
  });
  testWidgets('opt-in native selection returns an original episode to Dart',
      (tester) async {
    final selected = <List<int>>[];
    var paused = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'show') return null;
      final snapshot = call.arguments as Map;
      expect(snapshot.toString(), isNot(contains('private.invalid')));
      return {
        'sessionId': snapshot['sessionId'],
        'revision': snapshot['revision'],
        'commandId': 'choose-999',
        'action': 'selected',
        'opaqueId': 'episode-998'
      };
    });
    await tester.pumpWidget(panel(
        (episode, road) => selected.add([episode, road]), opening: () async {
      paused++;
    }));
    await tester.tap(find.byKey(const ValueKey('episode-browser-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('episode-quick-browser')));
    await tester.pumpAndSettle();
    expect(selected, [
      [999, 0]
    ]);
    expect(paused, 1);
  });
  testWidgets('native Back returns focus and performs no playback action',
      (tester) async {
    final selected = <int>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'show') return null;
      final snapshot = call.arguments as Map;
      return {
        'sessionId': snapshot['sessionId'],
        'revision': snapshot['revision'],
        'commandId': 'back',
        'action': 'cancelled'
      };
    });
    await tester.pumpWidget(panel((episode, _) => selected.add(episode)));
    await tester.tap(find.byKey(const ValueKey('episode-browser-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('episode-quick-browser')));
    await tester.pumpAndSettle();
    expect(selected, isEmpty);
    expect(
        FocusManager.instance.primaryFocus?.debugLabel, 'TV episode browser');
  });
  testWidgets('disposed Flutter route rejects a late native selection',
      (tester) async {
    final response = Completer<Object?>();
    Map? snapshot;
    final selected = <int>[];
    final cancelled = <Map>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'cancel') {
        cancelled.add(call.arguments as Map);
        return null;
      }
      snapshot = call.arguments as Map;
      return response.future;
    });
    await tester.pumpWidget(panel((episode, _) => selected.add(episode)));
    await tester.tap(find.byKey(const ValueKey('episode-browser-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('episode-quick-browser')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    response.complete({
      'sessionId': snapshot!['sessionId'],
      'revision': snapshot!['revision'],
      'commandId': 'late',
      'action': 'selected',
      'opaqueId': 'episode-998'
    });
    await tester.pumpAndSettle();
    expect(cancelled, hasLength(1));
    expect(selected, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('list string collisions cannot revive an old native snapshot',
      (tester) async {
    final response = Completer<Object?>();
    Map? snapshot;
    var cancelled = 0;
    final selected = <int>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'cancel') {
        cancelled++;
        return null;
      }
      snapshot = call.arguments as Map;
      return response.future;
    });
    Widget colliding(bool replacement) => MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 400,
                height: 460,
                child: EpisodeSelectionPanel(
                  title: '同名列表',
                  selectedRoad: 0,
                  selectedEpisode: 1,
                  roads: [
                    Road(
                        name: '线路',
                        data: replacement ? ['/a', '/b'] : ['/a, /b'],
                        identifier: replacement ? ['EP1', 'EP2'] : ['EP1, EP2'])
                  ],
                  downloads: const {},
                  onEpisodeSelected: (episode, _) => selected.add(episode),
                ))));
    await tester.pumpWidget(colliding(false));
    await tester.tap(find.byKey(const ValueKey('episode-browser-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('episode-quick-browser')));
    await tester.pump();
    await tester.pumpWidget(colliding(true));
    await tester.pump();
    response.complete({
      'sessionId': snapshot!['sessionId'],
      'revision': snapshot!['revision'],
      'commandId': 'stale-collision',
      'action': 'selected',
      'opaqueId': 'episode-0'
    });
    await tester.pumpAndSettle();
    expect(cancelled, 1);
    expect(selected, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
