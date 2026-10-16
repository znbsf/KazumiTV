import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/bean/dialog/dialog.dart';
import 'package:kazumi/bean/widget/tv_app_shell.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/update/startup_rule_update_check.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late PathProviderPlatform paths;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('tv_action_prompt_');
    paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = paths;
    await dir.delete(recursive: true);
  });
  setUp(() {
    TvMode.setEnabledForTesting(true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.predidit.kazumi/tv_navigation'),
            (_) async => null);
  });
  tearDown(() => TvMode.setEnabledForTesting(false));

  Future<FocusNode> mount(WidgetTester tester, VoidCallback background) async {
    final focus = FocusNode();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: rootNavigatorKey,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      navigatorObservers: [KazumiDialog.observer],
      builder: (_, child) => TvAppShell(child: child!),
      home: Scaffold(
          body: FocusScope(
              child: Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.arrowRight) {
            background();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextButton(
            autofocus: true,
            focusNode: focus,
            onPressed: background,
            child: const Text('home')),
      ))),
    ));
    await tester.pumpAndSettle();
    addTearDown(() async {
      while (KazumiDialog.observer.hasKazumiDialog) {
        KazumiDialog.dismiss();
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      focus.dispose();
    });
    return focus;
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'startup action owns remote focus, persists, cancels and restores home',
      (tester) async {
    var background = 0, updates = 0;
    final home = await mount(tester, () => background++);
    await runStartupRuleUpdateCheck(
        check: () async => 2, update: () => updates++);
    await tester.pumpAndSettle();
    expect(home.hasFocus, isFalse);
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('全部更新'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(background, 0);
    await rootNavigatorKey.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(updates, 0);
    expect(home.hasFocus, isTrue);
    await key(tester, LogicalKeyboardKey.select);
    expect(background, 1);
  });

  testWidgets(
      'remote selects action once and consecutive prompts stay separate',
      (tester) async {
    var updates = 0, second = 0;
    await mount(tester, () {});
    await runStartupRuleUpdateCheck(
        check: () async => 1, update: () => updates++);
    KazumiDialog.showToast(
        message: 'reconnect',
        showActionButton: true,
        actionLabel: 'retry',
        onActionPressed: () => second++);
    await tester.pumpAndSettle();
    expect(find.text('reconnect'), findsNothing);
    expect(find.text('全部更新'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.select);
    expect(updates, 1);
    expect(find.text('reconnect'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.select); // default cancel
    expect(second, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
      'no updates and failed check do not steal focus; slow result still works',
      (tester) async {
    final home = await mount(tester, () {});
    var updates = 0;
    await runStartupRuleUpdateCheck(
        check: () async => 0, update: () => updates++);
    await runStartupRuleUpdateCheck(
        check: () async => throw StateError('offline'),
        update: () => updates++);
    await tester.pumpAndSettle();
    expect(home.hasFocus, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    final response = Completer<int>();
    final pending = runStartupRuleUpdateCheck(
        check: () => response.future, update: () => updates++);
    await tester.pump(const Duration(seconds: 10));
    expect(home.hasFocus, isTrue);
    response.complete(3);
    await pending;
    await tester.pumpAndSettle();
    expect(find.text('全部更新'), findsOneWidget);
    expect(home.hasFocus, isFalse);
    await key(tester, LogicalKeyboardKey.select);
    expect(updates, 0);
  });

  testWidgets('passive TV notices and desktop actions remain snackbars',
      (tester) async {
    final home = await mount(tester, () {});
    KazumiDialog.showToast(message: 'failure', showActionButton: true);
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(home.hasFocus, isTrue);
    TvMode.setEnabledForTesting(false);
    KazumiDialog.showToast(
        message: 'desktop', showActionButton: true, onActionPressed: () {});
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('desktop'), findsOneWidget);
  });

  testWidgets('failed action cannot strand the queue or underlying focus',
      (tester) async {
    final home = await mount(tester, () {});
    var attempted = 0;
    KazumiDialog.showToast(
        message: 'first',
        showActionButton: true,
        onActionPressed: () {
          attempted++;
          throw StateError('controlled action failure');
        });
    KazumiDialog.showToast(
        message: 'second', showActionButton: true, onActionPressed: () {});
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.select);
    expect(attempted, 1);
    expect(find.text('second'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.select);
    expect(home.hasFocus, isTrue);
  });

  testWidgets('duplicate check results yield one prompt and one action',
      (tester) async {
    await mount(tester, () {});
    var updates = 0;
    for (var i = 0; i < 3; i++) {
      await runStartupRuleUpdateCheck(
          check: () async => 2, update: () => updates++);
    }
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.arrowRight);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(updates, 1);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
      'queued prompt from a destroyed page is skipped, including later calls',
      (tester) async {
    final home = await mount(tester, () {});
    final owner = home.context!;
    final page = ModalRoute.of(owner)!;
    var actions = 0;
    KazumiDialog.showToast(
        message: 'first', showActionButton: true, onActionPressed: () {});
    KazumiDialog.showToast(
        context: owner,
        message: 'obsolete',
        showActionButton: true,
        onActionPressed: () => actions++);
    await tester.pumpAndSettle();
    rootNavigatorKey.currentState!.replace(
      oldRoute: page,
      newRoute: MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('replacement'))),
    );
    await tester.pumpAndSettle();
    expect(owner.mounted, isFalse);
    await rootNavigatorKey.currentState!.maybePop();
    await tester.pumpAndSettle();
    KazumiDialog.showToast(
        context: owner,
        message: 'late',
        showActionButton: true,
        onActionPressed: () => actions++);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(actions, 0);
  });

  testWidgets(
      'obsolete reconnect is skipped before display and before accepting',
      (tester) async {
    await mount(tester, () {});
    var current = true, actions = 0;
    void reconnect() => KazumiDialog.showToast(
        message: 'SyncPlay: disconnected',
        showActionButton: true,
        actionLabel: '重新连接',
        isActionCurrent: () => current,
        onActionPressed: () => actions++);
    KazumiDialog.showToast(
        message: 'first', showActionButton: true, onActionPressed: () {});
    reconnect();
    await tester.pumpAndSettle();
    current = false;
    await key(tester, LogicalKeyboardKey.select);
    expect(find.byType(AlertDialog), findsNothing);
    current = true;
    reconnect();
    await tester.pumpAndSettle();
    current = false;
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.select);
    expect(actions, 0);
  });

  testWidgets(
      'existing plain AlertDialog is reachable by D-pad and isolates home',
      (tester) async {
    var background = 0;
    final home = await mount(tester, () => background++);
    unawaited(KazumiDialog.show<void>(
        builder: (context) => AlertDialog(
              title: const Text('existing confirmation'),
              actions: [
                TextButton(
                    onPressed: () => KazumiDialog.dismiss(context: context),
                    child: const Text('cancel'))
              ],
            )));
    await tester.pumpAndSettle();
    expect(home.hasFocus, isFalse);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.select);
    expect(find.byType(AlertDialog), findsNothing);
    expect(background, 0);
    expect(home.hasFocus, isTrue);
  });
}
