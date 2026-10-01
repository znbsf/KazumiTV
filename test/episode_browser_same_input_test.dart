import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/video/episode_selection_panel.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.predidit.kazumi/episode_browser');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final cases = File('android/app/src/test/resources/episode_browser_cases.csv')
      .readAsLinesSync()
      .skip(1)
      .where((line) => line.isNotEmpty)
      .map((line) => line.split(','))
      .toList();
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() {
    TvMode.setEnabledForTesting(false);
    messenger.setMockMethodCallHandler(channel, null);
  });
  Widget panel(int count, int ordinal, String label,
          void Function(int, int) select) =>
      MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 400,
                  height: 460,
                  child: EpisodeSelectionPanel(
                      title: '共享选集输入',
                      roads: [
                        Road(
                            name: '线路',
                            data: List.generate(
                                count, (i) => 'https://private.invalid/$i'),
                            identifier: List.generate(count,
                                (i) => i == ordinal - 1 ? label : '集${i + 1}'))
                      ],
                      selectedRoad: 0,
                      selectedEpisode: ordinal,
                      seenEpisodes: {ordinal},
                      onEpisodeSelected: select,
                      downloads: const {}))));

  for (final fields in cases) {
    final name = fields[0], label = fields[3], action = fields[6];
    final count = int.parse(fields[1]), ordinal = int.parse(fields[2]);
    for (final native in [false, true]) {
      testWidgets(
          '$name shared input ${native ? 'native command' : 'Flutter fallback'}',
          (tester) async {
        final selected = <int>[];
        var nativeCalls = 0;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'show') return null;
          nativeCalls++;
          final snapshot = call.arguments as Map;
          final items = snapshot['items'] as List;
          final item = items[ordinal - 1] as Map;
          expect(item, {
            'opaqueId': 'episode-${ordinal - 1}',
            'label': label,
            'current': true,
            'seen': true
          });
          expect(snapshot.toString(), isNot(contains('private.invalid')));
          return {
            'sessionId': snapshot['sessionId'],
            'revision': snapshot['revision'],
            'commandId': name,
            'action': action,
            if (action == 'selected') 'opaqueId': item['opaqueId']
          };
        });
        await tester.pumpWidget(panel(count, ordinal, label, (episode, road) {
          expect(road, 0);
          selected.add(episode);
        }));
        if (native) {
          await tester
              .tap(find.byKey(const ValueKey('episode-browser-toggle')));
          await tester.pump();
        }
        await tester.tap(find.byKey(const ValueKey('episode-quick-browser')));
        await tester.pumpAndSettle();
        if (!native) {
          if (action == 'selected') {
            await tester.enterText(
                find.byKey(const ValueKey('episode-jump-number')), '$ordinal');
            await tester.tap(find.text('定位'));
            await tester.pumpAndSettle();
            expect(selected, isEmpty, reason: 'Location alone must not play');
            expect(FocusManager.instance.primaryFocus?.debugLabel,
                'TV episode 0:$ordinal');
            await tester.sendKeyEvent(LogicalKeyboardKey.select);
          } else {
            await tester.tap(find.text('取消'));
          }
          await tester.pumpAndSettle();
        }
        expect(nativeCalls, native ? 1 : 0,
            reason: 'Default switch must stay off');
        expect(selected, action == 'selected' ? [ordinal] : isEmpty);
        if (action == 'cancelled') {
          expect(FocusManager.instance.primaryFocus?.debugLabel,
              'TV episode browser');
        }
        if (native) {
          debugPrint(
              'EPISODE_CONTRACT|$name|${action == 'selected' ? ordinal : 'none'}|$action|$label');
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets(
      'missing native component switches off and completes the Flutter fallback',
      (tester) async {
    final selected = <int>[];
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'show') {
        calls++;
        throw MissingPluginException('fixture component unavailable');
      }
      return null;
    });
    await tester.pumpWidget(
        panel(201, 1, 'EP1', (episode, _) => selected.add(episode)));
    await tester.tap(find.byKey(const ValueKey('episode-browser-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('episode-quick-browser')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('episode-jump-number')), '151');
    await tester.tap(find.text('定位'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(selected, [151]);
    await tester.tap(find.byKey(const ValueKey('episode-quick-browser')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('episode-jump-number')), findsOneWidget);
    expect(calls, 1,
        reason: 'The failed native switch must remain off for this panel');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
