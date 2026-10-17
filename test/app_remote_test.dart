import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/services/platform/app_remote.dart';

void main() {
  Future<bool> tap(AppRemote remote, String key) =>
      remote.dispatch(key, revision: remote.state['revision'] as int);

  testWidgets('real focused buttons support direction and activation',
      (tester) async {
    final remote = AppRemote();
    final lease = remote.attachShell();
    addTearDown(lease.release);
    var first = 0, second = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Row(children: [
      TextButton(
          autofocus: true,
          onPressed: () => first++,
          child: const Text('first')),
      TextButton(onPressed: () => second++, child: const Text('second')),
    ]))));
    await tester.pumpAndSettle();
    expect(await tap(remote, 'ok'), isTrue);
    expect(first, 1);
    expect(await tap(remote, 'right'), isTrue);
    await tester.pumpAndSettle();
    expect(await tap(remote, 'ok'), isTrue);
    expect(second, 1);
    expect(await tap(remote, 'power'), isFalse);
    expect(await tap(remote, 'channelUp'), isFalse);
  });

  testWidgets('focused component consumes arrows before traversal',
      (tester) async {
    final remote = AppRemote();
    final lease = remote.attachShell();
    addTearDown(lease.release);
    var value = 0;
    await tester.pumpWidget(MaterialApp(
        home: Focus(
            autofocus: true,
            onKeyEvent: (_, event) {
              if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                value++;
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: const SizedBox(width: 100, height: 100))));
    await tester.pumpAndSettle();
    expect(await tap(remote, 'right'), isTrue);
    expect(value, 1);
    expect(HardwareKeyboard.instance.logicalKeysPressed, isEmpty);
  });

  testWidgets('route back and stale route command are bounded', (tester) async {
    final remote = AppRemote();
    final lease = remote.attachShell();
    addTearDown(lease.release);
    await tester.pumpWidget(MaterialApp(
        navigatorKey: rootNavigatorKey,
        home: TextButton(
            autofocus: true, onPressed: () {}, child: const Text('root'))));
    await tester.pumpAndSettle();
    final old = remote.state['revision'] as int;
    unawaited(showDialog<void>(
        context: rootNavigatorKey.currentContext!,
        builder: (_) => AlertDialog(content: const Text('dialog'), actions: [
              TextButton(
                  autofocus: true, onPressed: () {}, child: const Text('stay'))
            ])));
    await tester.pumpAndSettle();
    expect(await remote.dispatch('ok', revision: old), isFalse);
    expect(await tap(remote, 'back'), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('dialog'), findsNothing);
  });

  testWidgets('context labels and lease lifetime gate actions', (tester) async {
    final remote = AppRemote();
    final shell = remote.attachShell();
    addTearDown(shell.release);
    var calls = 0;
    final context = remote.register(
        label: '播放器',
        commands: () => {
              'red': AppRemoteCommand(
                  label: '红 · 弹幕',
                  invoke: () {
                    calls++;
                    return true;
                  }),
            });
    await tester.pumpWidget(MaterialApp(
        home: TextButton(
            autofocus: true, onPressed: () {}, child: const Text('root'))));
    await tester.pumpAndSettle();
    expect(remote.state['context'], '播放器');
    final revision = remote.state['revision'] as int;
    expect(await remote.dispatch('red', revision: revision), isTrue);
    expect(await remote.dispatch('red', revision: revision), isFalse);
    expect(calls, 1);
    context.release();
    expect(await tap(remote, 'red'), isFalse);
  });

  testWidgets('busy dispatch cannot queue a second command', (tester) async {
    final remote = AppRemote();
    final shell = remote.attachShell();
    addTearDown(shell.release);
    final completion = Completer<bool>();
    var calls = 0;
    final owner = remote.register(
        label: 'test',
        commands: () => {
              'info': AppRemoteCommand(
                  label: '信息',
                  invoke: () {
                    calls++;
                    return completion.future;
                  })
            });
    addTearDown(owner.release);
    await tester.pumpWidget(MaterialApp(
        home: TextButton(
            autofocus: true, onPressed: () {}, child: const Text('root'))));
    await tester.pumpAndSettle();
    final first = tap(remote, 'info');
    expect(await tap(remote, 'info'), isFalse);
    completion.complete(true);
    expect(await first, isTrue);
    expect(calls, 1);
  });

  testWidgets('background disables all capabilities', (tester) async {
    final remote = AppRemote();
    final shell = remote.attachShell();
    addTearDown(shell.release);
    await tester.pumpWidget(MaterialApp(
        home: TextButton(
            autofocus: true, onPressed: () {}, child: const Text('root'))));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(remote.state['keys'], isEmpty);
    expect(await tap(remote, 'ok'), isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}
