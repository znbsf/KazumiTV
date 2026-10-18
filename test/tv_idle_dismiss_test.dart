import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/tv_idle_dismiss.dart';
import 'package:kazumi/services/platform/app_remote.dart';

void main() {
  Future<BuildContext> mount(WidgetTester tester, VoidCallback dismiss,
      {ValueNotifier<bool>? enabled}) async {
    late BuildContext page;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      page = context;
      return Scaffold(
          body: ValueListenableBuilder<bool>(
        valueListenable: enabled ?? ValueNotifier(true),
        builder: (_, value, __) => TvIdleDismiss(
            enabled: value,
            onDismiss: dismiss,
            child: Focus(
                autofocus: true,
                onKeyEvent: (_, __) => KeyEventResult.handled,
                child: const SizedBox(
                    width: 300, height: 300, child: Text('episodes')))),
      ));
    })));
    await tester.pump();
    return page;
  }

  testWidgets('closes at three seconds; state polling does not renew',
      (tester) async {
    var closed = 0;
    final enabled = ValueNotifier(true);
    await mount(tester, () => closed++, enabled: enabled);
    await tester.pump(const Duration(milliseconds: 2900));
    expect(closed, 0);
    AppRemote.instance.state;
    await tester.pump(const Duration(milliseconds: 100));
    expect(closed, 1);
    await tester.pumpWidget(const SizedBox());
    enabled.dispose();
  });

  testWidgets('handled hardware keys and pointer interaction reset inactivity',
      (tester) async {
    var closed = 0;
    await mount(tester, () => closed++);
    await tester.pump(const Duration(seconds: 2));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(seconds: 2));
    expect(closed, 0);
    await tester.tap(find.text('episodes'));
    await tester.pump(const Duration(milliseconds: 2999));
    expect(closed, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(closed, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'accepted phone command renews; rejected commands and state polling do not',
      (tester) async {
    var closed = 0;
    await mount(tester, () => closed++);
    final remote = AppRemote.instance;
    final shell = remote.attachShell();
    final owner = remote.register(
        label: 'test',
        commands: () =>
            {'test': AppRemoteCommand(label: 'test', invoke: () => true)});
    addTearDown(shell.release);
    addTearDown(owner.release);
    await tester.pump(const Duration(seconds: 2));
    expect(
        await remote.dispatch('test',
            revision: remote.state['revision'] as int),
        true);
    await tester.pump(const Duration(seconds: 2));
    expect(closed, 0);
    expect(await remote.dispatch('test', revision: -1), false);
    await tester.pump(const Duration(seconds: 1));
    expect(closed, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'covered dialog and comments are retained; returning starts a fresh timer',
      (tester) async {
    var closed = 0;
    final enabled = ValueNotifier(true);
    final context = await mount(tester, () => closed++, enabled: enabled);
    await tester.pump(const Duration(seconds: 2));
    showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('keep dialog')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    expect(closed, 0);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(closed, 0);
    enabled.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(closed, 0);
    enabled.value = true;
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(closed, 1);
    await tester.pumpWidget(const SizedBox());
    enabled.dispose();
  });

  testWidgets(
      'background and disposal cancel timer, resume gives full interval',
      (tester) async {
    var closed = 0;
    await mount(tester, () => closed++);
    await tester.pump(const Duration(seconds: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 5));
    expect(closed, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 2));
    expect(closed, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    expect(closed, 0);
  });
}
