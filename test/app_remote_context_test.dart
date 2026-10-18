import 'dart:async';
import 'package:kazumi/pages/player/tv_playback_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/platform/app_remote.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/platform/tv_navigation.dart';
import 'package:kazumi/pages/player/player_keyboard_shortcuts.dart';

Set<String> keys() => (AppRemote.instance.state['keys'] as List)
    .map((v) => (v as Map)['id'] as String)
    .toSet();
Future<bool> tap(String key) => AppRemote.instance
    .dispatch(key, revision: AppRemote.instance.state['revision'] as int);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TvMode.setEnabledForTesting(true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.predidit.kazumi/tv_remote'),
            (_) async => null);
  });
  tearDown(() => TvMode.setEnabledForTesting(false));
  testWidgets('pending detail playback does not lock subsequent remote taps',
      (tester) async {
    final lease = AppRemote.instance.attachShell();
    addTearDown(lease.release);
    final pending = Completer<void>();
    var activations = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TvDetailPlayShortcut(
                onPlay: () => pending.future,
                child: TextButton(
                    autofocus: true,
                    onPressed: () => activations++,
                    child: const Text('Source picker action'))))));
    await tester.pumpAndSettle();
    bool? completed;
    final first = tap('playPause').then((value) => completed = value);
    await tester.pump();
    expect(completed, isTrue,
        reason: 'Dispatch must finish while the playback future is pending');
    expect(pending.isCompleted, isFalse);
    expect(await tap('ok'), isTrue);
    expect(activations, 1);
    pending.complete();
    await first;
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('detail exposes start watching only on current non-editor route',
      (tester) async {
    final lease = AppRemote.instance.attachShell();
    addTearDown(lease.release);
    final nav = GlobalKey<NavigatorState>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        home: Scaffold(
            body: TvDetailPlayShortcut(
                onPlay: () async {
                  calls++;
                },
                child: const TextButton(
                    onPressed: null, child: Text('detail'))))));
    // Disabled buttons cannot own focus; route scope is a valid current context.
    nav.currentState!.focusNode.requestFocus();
    await tester.pumpAndSettle();
    expect(keys(), contains('playPause'));
    expect(await tap('playPause'), isTrue);
    expect(calls, 1);
    nav.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: TextField(autofocus: true))));
    await tester.pumpAndSettle();
    expect(keys(), isNot(contains('playPause')));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'player exposes real actions, no channel alias, tap releases forward',
      (tester) async {
    final lease = AppRemote.instance.attachShell();
    addTearDown(lease.release);
    final scope = FocusNode();
    final nav = GlobalKey<NavigatorState>();
    var down = 0, up = 0, menu = 0;
    await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        home: Scaffold(
            body: Focus(
                focusNode: scope,
                autofocus: true,
                child: PlayerKeyboardShortcuts(
                    focusScopeNode: scope,
                    shortcuts: withTvRemoteShortcuts({
                      'forward': ['Arrow Right']
                    }),
                    actions: {
                      'forward': () {
                        down++;
                      },
                      'showremotehelp': () {
                        menu++;
                      }
                    },
                    longPressActions: {
                      'forward': PlayerLongPressShortcutActions(
                          onRepeat: () {},
                          onRelease: () {
                            up++;
                          },
                          onCancel: () {})
                    })))));
    await tester.pumpAndSettle();
    expect(keys(), contains('menu'));
    expect(keys(), isNot(contains('channelUp')));
    expect(await tap('menu'), isTrue);
    expect(menu, 1);
    expect(await tap('right'), isTrue);
    expect(down, 1);
    expect(up, 1);
    nav.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: TextField(autofocus: true))));
    await tester.pumpAndSettle();
    expect(keys(), isNot(contains('menu')));
    await tester.pumpWidget(const SizedBox());
    scope.dispose();
  });
  testWidgets(
      'info overlay publishes close only while current and restores context',
      (tester) async {
    final lease = AppRemote.instance.attachShell();
    addTearDown(lease.release);
    final focus = FocusNode();
    final presenter = TvPlaybackInfoPresenter();
    late BuildContext page;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      page = context;
      return Scaffold(
          body: TextButton(
              focusNode: focus,
              autofocus: true,
              onPressed: () {},
              child: const Text('entry')));
    })));
    await tester.pumpAndSettle();
    final closed = presenter.show(page,
        fallbackFocus: focus,
        builder: (_) => const AlertDialog(content: Text('info'), actions: [
              TextButton(autofocus: true, onPressed: null, child: Text('close'))
            ]));
    await tester.pumpAndSettle();
    expect(keys(), containsAll(['info', 'blue']));
    expect(await tap('blue'), isTrue);
    await tester.pumpAndSettle();
    await closed;
    expect(keys(), isNot(contains('info')));
    expect(focus.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    focus.dispose();
  });
  testWidgets('player remote aliases invoke exactly their real shortcut action',
      (tester) async {
    final lease = AppRemote.instance.attachShell();
    addTearDown(lease.release);
    final scope = FocusNode();
    final calls = <String>[];
    const aliases = {
      'info': 'showdetails',
      'menu': 'showremotehelp',
      'red': 'toggledanmaku',
      'green': 'togglefavorite',
      'yellow': 'showepisodes',
      'blue': 'showdetails',
      'playPause': 'playorpause',
      'play': 'play',
      'pause': 'pause',
      'stop': 'exitplayer',
      'rewind': 'rewind',
      'fastForward': 'forward',
      'previous': 'prev',
      'next': 'next',
      'guide': 'showepisodes',
    };
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Focus(
                focusNode: scope,
                autofocus: true,
                child: PlayerKeyboardShortcuts(
                    focusScopeNode: scope,
                    shortcuts: withTvRemoteShortcuts({}),
                    actions: {
                      for (final action in aliases.values.toSet())
                        action: () => calls.add(action),
                    })))));
    await tester.pumpAndSettle();
    expect(keys(), containsAll(aliases.keys));
    expect(keys().intersection({'channelUp', 'channelDown', 'prev'}),
        isEmpty);
    for (final entry in aliases.entries) {
      calls.clear();
      final revision = AppRemote.instance.state['revision'] as int;
      expect(await AppRemote.instance.dispatch(entry.key, revision: revision),
          isTrue);
      expect(calls, [entry.value]);
      expect(await AppRemote.instance.dispatch(entry.key, revision: revision),
          isFalse,
          reason: 'Replaying a consumed revision must not repeat effects');
      expect(calls, [entry.value]);
    }
    await tester.pumpWidget(const SizedBox());
    expect(keys(), isNot(contains('menu')));
    scope.dispose();
  });

  testWidgets('player capability changes reject stale and covered commands',
      (tester) async {
    final lease = AppRemote.instance.attachShell();
    addTearDown(lease.release);
    final scope = FocusNode();
    final editorFocus = FocusNode();
    final nav = GlobalKey<NavigatorState>();
    var blocked = false;
    var allowInfo = true;
    final calls = <String>[];
    await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        home: Scaffold(
            body: Focus(
                focusNode: scope,
                autofocus: true,
                child: Column(children: [
                  PlayerKeyboardShortcuts(
                      focusScopeNode: scope,
                      shortcuts: withTvRemoteShortcuts({}),
                      isBlocked: () => blocked,
                      shouldHandleAction: (action, _) =>
                          action != 'showdetails' || allowInfo,
                      actions: {
                        'showdetails': () => calls.add('info'),
                        'showremotehelp': () => calls.add('menu'),
                      }),
                  TextField(focusNode: editorFocus),
                ])))));
    await tester.pumpAndSettle();
    expect(keys(), containsAll(['info', 'blue', 'menu']));
    expect(keys(), isNot(contains('red')),
        reason: 'A shortcut alias alone must not advertise a missing action');
    expect(await tap('red'), isFalse);
    final enabledRevision = AppRemote.instance.state['revision'] as int;
    allowInfo = false;
    expect(await AppRemote.instance.dispatch('info', revision: enabledRevision),
        isFalse);
    expect(keys(), isNot(contains('info')));
    expect(keys(), isNot(contains('blue')));
    expect(await tap('menu'), isTrue);
    expect(calls, ['menu']);
    blocked = true;
    expect(keys(), isNot(contains('menu')));
    expect(await tap('menu'), isFalse);
    blocked = false;
    allowInfo = true;
    editorFocus.requestFocus();
    await tester.pumpAndSettle();
    expect(keys(), isNot(contains('info')),
        reason: 'An editor inside the player scope must own its input');
    scope.requestFocus();
    await tester.pumpAndSettle();
    expect(keys(), contains('info'));
    final beforeCover = AppRemote.instance.state['revision'] as int;
    nav.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
            body: TextButton(
                autofocus: true,
                onPressed: () {},
                child: const Text('Covered route')))));
    await tester.pumpAndSettle();
    expect(keys(), isNot(contains('menu')));
    expect(await AppRemote.instance.dispatch('menu', revision: beforeCover),
        isFalse);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    scope.requestFocus();
    await tester.pumpAndSettle();
    expect(keys(), contains('menu'));
    expect(await tap('info'), isTrue);
    expect(calls, ['menu', 'info']);
    await tester.pumpWidget(const SizedBox());
    editorFocus.dispose();
    scope.dispose();
  });
}
