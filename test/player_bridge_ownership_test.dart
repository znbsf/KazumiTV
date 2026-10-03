import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/player_keyboard_shortcuts.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/platform/owned_method_channel.dart';
import 'package:kazumi/services/player/pip_utils.dart';

void main() {
  testWidgets('returning to an owner cannot revive its older async request',
      (tester) async {
    final owners =
        OwnedMethodChannel(const MethodChannel('test/owner_generation'));
    final old = owners.claim((_) async {});
    final ownsOldRequest = old.captureOwnership();
    expect(ownsOldRequest(), isTrue);
    final newer = owners.claim((_) async {});
    newer.release();
    expect(old.isCurrent, isTrue);
    expect(ownsOldRequest(), isFalse);
    final ownsNewRequest = old.captureOwnership();
    newer.release();
    expect(ownsNewRequest(), isTrue);
    old.release();
    expect(ownsNewRequest(), isFalse);
  });
  const channel = MethodChannel('com.predidit.kazumi/tv_remote');
  for (final removeOld in [true, false]) {
    testWidgets(
        removeOld
            ? 'disposing an old player cannot clear the new native remote owner'
            : 'returning from a newer player restores the surviving remote owner',
        (tester) async {
      TvMode.setEnabledForTesting(true);
      final oldScope = FocusScopeNode();
      final newScope = FocusScopeNode();
      final active = <bool>[];
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        if (call.method == 'setPlayerActive') {
          active.add((call.arguments as Map)['active'] as bool);
        }
        return null;
      });
      addTearDown(() {
        TvMode.setEnabledForTesting(false);
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        oldScope.dispose();
        newScope.dispose();
      });
      Widget app({bool old = true, bool newer = false}) => MaterialApp(
              home: Column(children: [
            if (old)
              FocusScope(
                  key: const ValueKey('old'),
                  node: oldScope,
                  child: PlayerKeyboardShortcuts(
                      focusScopeNode: oldScope,
                      shortcuts: const {},
                      actions: {'playorpause': () => calls.add('old')})),
            if (newer)
              FocusScope(
                  key: const ValueKey('new'),
                  node: newScope,
                  child: PlayerKeyboardShortcuts(
                      focusScopeNode: newScope,
                      shortcuts: const {},
                      actions: {'playorpause': () => calls.add('new')})),
          ]));
      Future<void> dispatch() async {
        final reply = Completer<void>();
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            channel.name,
            const StandardMethodCodec()
                .encodeMethodCall(const MethodCall('dispatch', 'playorpause')),
            (_) => reply.complete());
        await reply.future;
      }

      await tester.pumpWidget(app());
      await tester.pumpWidget(app(newer: true));
      await dispatch();
      expect(calls, ['new']);
      calls.clear();
      await tester.pumpWidget(app(old: !removeOld, newer: removeOld));
      await dispatch();
      expect(calls, [removeOld ? 'new' : 'old']);
      expect(active, isNot(contains(false)));
      await tester.pumpWidget(const SizedBox());
      expect(active.last, isFalse);
    });
  }
  testWidgets('PIP dispatcher leases isolate lifetimes and restore callbacks',
      (tester) async {
    const pip = MethodChannel('test/pip_owner_contract');
    final active = <bool>[];
    final activations = <String>[];
    final calls = <String>[];
    final owners = OwnedMethodChannel(pip, onActiveChanged: active.add);
    final old = owners.claim((call) async {
      calls.add('old:${call.method}');
    }, onActivated: () => activations.add('old'));
    final newer = owners.claim((call) async {
      calls.add('new:${call.method}');
    }, onActivated: () => activations.add('new'));
    Future<void> dispatch() async {
      final reply = Completer<void>();
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          pip.name,
          const StandardMethodCodec().encodeMethodCall(
              const MethodCall('onAction', {'action': 'play_pause'})),
          (_) => reply.complete());
      await reply.future;
    }

    await dispatch();
    newer.release();
    newer.release();
    await dispatch();
    expect(calls, ['new:onAction', 'old:onAction']);
    expect(activations, ['old', 'new', 'old']);
    expect(old.isCurrent, isTrue);
    expect(newer.isCurrent, isFalse);
    expect(active, [true]);
    old.release();
    old.release();
    expect(active, [true, false]);
    expect(owners.hasOwners, isFalse);
  });
  testWidgets('actual PIP registration is released only by its own lease',
      (tester) async {
    final old =
        PipUtils.initPipHandler(onAction: (_) async {}, onModeChanged: (_) {});
    final newer =
        PipUtils.initPipHandler(onAction: (_) async {}, onModeChanged: (_) {});
    expect(old.isCurrent, isFalse);
    expect(newer.isCurrent, isTrue);
    PipUtils.disposePipHandler(old);
    expect(PipUtils.androidPIPInited, isTrue);
    expect(newer.isCurrent, isTrue);
    PipUtils.disposePipHandler(newer);
    expect(PipUtils.androidPIPInited, isFalse);
  });
}
