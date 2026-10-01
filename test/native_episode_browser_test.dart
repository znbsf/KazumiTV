import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/platform/native_episode_browser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.predidit.kazumi/episode_browser');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  EpisodeBrowserSnapshot snapshot() => EpisodeBrowserSnapshot(
        sessionId: 'session-1',
        revision: 7,
        initialOpaqueId: 'one',
        items: const [
          EpisodeBrowserItem(opaqueId: 'one', label: '第1集'),
          EpisodeBrowserItem(opaqueId: 'two', label: '第2集', seen: true)
        ],
      );
  Map<String, Object> selected() => {
        'sessionId': 'session-1',
        'revision': 7,
        'commandId': 'command-1',
        'action': 'selected',
        'opaqueId': 'two'
      };
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('selected command authorizes one known opaque id exactly once', () {
    final gate = EpisodeBrowserCommandGate(snapshot());
    expect(gate.consume(selected(), current: true), 'two');
    expect(gate.consume({...selected(), 'commandId': 'another'}, current: true),
        isNull);
  });
  test('cancelled command never selects and closes the UI session', () {
    final gate = EpisodeBrowserCommandGate(snapshot());
    expect(
        gate.consume({
          'sessionId': 'session-1',
          'revision': 7,
          'commandId': 'cancel',
          'action': 'cancelled'
        }, current: true),
        isNull);
    expect(gate.consume(selected(), current: true), isNull);
  });
  for (final invalid in <String, Object>{
    'sessionId': 'expired',
    'revision': 6,
    'opaqueId': 'outside',
    'action': 'play',
    'commandId': '',
  }.entries) {
    test('rejects unauthorized ${invalid.key} without a Dart action', () {
      final gate = EpisodeBrowserCommandGate(snapshot());
      expect(
          gate.consume({...selected(), invalid.key: invalid.value},
              current: true),
          isNull);
    });
  }
  test('rejects float revisions, unexpected data and superseded owners', () {
    final gate = EpisodeBrowserCommandGate(snapshot());
    expect(
        gate.consume({...selected(), 'revision': 7.0}, current: true), isNull);
    expect(
        gate.consume({...selected(), 'sourceUrl': 'https://private.invalid'},
            current: true),
        isNull);
    expect(gate.consume(selected(), current: false), isNull);
  });
  test('snapshot crosses the channel with only display data', () {
    final map = snapshot().toMap();
    expect(map.keys.toSet(),
        {'sessionId', 'revision', 'initialOpaqueId', 'items'});
    expect(jsonEncode(map), isNot(contains('https://')));
    expect(
        () => EpisodeBrowserSnapshot(sessionId: 's', revision: 0, items: const [
              EpisodeBrowserItem(opaqueId: 'one', label: 'a'),
              EpisodeBrowserItem(opaqueId: 'one', label: 'b')
            ]),
        throwsArgumentError);
  });
  test('native completion is ignored after local cancellation', () async {
    final response = Completer<Object?>();
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'show' ? response.future : null;
    });
    final client = NativeEpisodeBrowser();
    final pending = client.show(snapshot(), isCurrent: () => true);
    await Future<void>.delayed(Duration.zero);
    await client.cancel();
    response.complete(selected());
    expect(await pending, isNull);
    expect(calls.last.method, 'cancel');
    expect(calls.last.arguments, {'sessionId': 'session-1', 'revision': 7});
    await client.dispose();
  });
  test('only one native request may own a client', () async {
    final response = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (_) => response.future);
    final client = NativeEpisodeBrowser();
    final first = client.show(snapshot(), isCurrent: () => true);
    expect(await client.show(snapshot(), isCurrent: () => true), isNull);
    response.complete(selected());
    expect(await first, 'two');
    await client.dispose();
  });
  test('unavailable native component offers a Flutter fallback', () async {
    messenger.setMockMethodCallHandler(channel,
        (_) async => throw PlatformException(code: 'episode_browser_not_tv'));
    final client = NativeEpisodeBrowser();
    await expectLater(client.show(snapshot(), isCurrent: () => true),
        throwsA(isA<EpisodeBrowserUnavailable>()));
    await client.dispose();
  });
}
