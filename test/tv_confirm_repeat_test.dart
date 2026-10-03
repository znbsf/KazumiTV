// Uses real Material default shortcuts; no replacement Activate mapping.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/bean/widget/tv_app_shell.dart';
import 'package:kazumi/bean/widget/tv_focusable_surface.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/storage/storage.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

const _confirmKeys = [
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.gameButtonA,
];

Widget _app(
  Widget child, {
  bool shell = true,
  GlobalKey<NavigatorState>? nav,
}) => MaterialApp(
  navigatorKey: nav,
  builder: shell ? (_, child) => TvAppShell(child: child!) : null,
  home: Scaffold(body: Center(child: child)),
);

void _cleanup(WidgetTester tester) {
  addTearDown(() async {
    for (final key in HardwareKeyboard.instance.logicalKeysPressed.toList()) {
      await tester.sendKeyUpEvent(key);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late PathProviderPlatform originalPaths;
  setUpAll(() async {
    temporary = await Directory.systemTemp.createTemp('kazumi_confirm_repeat_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(temporary.path);
    Hive.init(temporary.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    await temporary.delete(recursive: true);
  });
  setUp(() {
    TvMode.setEnabledForTesting(true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.predidit.kazumi/tv_navigation'),
          (_) async => null,
        );
  });
  tearDown(() {
    TvMode.setEnabledForTesting(false);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.predidit.kazumi/tv_navigation'),
          null,
        );
  });

  testWidgets('TV held SELECT cannot activate the next route', (tester) async {
    const key = LogicalKeyboardKey.select;
    _cleanup(tester);
    final navigator = GlobalKey<NavigatorState>();
    var detailOpens = 0;
    var nextOpens = 0;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (homeContext) => TvFocusableSurface(
            autofocus: true,
            onPressed: () {
              detailOpens++;
              Navigator.of(homeContext).push(
                MaterialPageRoute<void>(
                  settings: const RouteSettings(name: '/detail'),
                  builder: (detailContext) => Scaffold(
                    body: Center(
                      child: TextButton(
                        autofocus: true,
                        onPressed: () {
                          nextOpens++;
                          Navigator.of(detailContext).push(
                            MaterialPageRoute<void>(
                              settings: const RouteSettings(name: '/next'),
                              builder: (_) =>
                                  const Scaffold(body: Text('next route')),
                            ),
                          );
                        },
                        child: const Text('start watching'),
                      ),
                    ),
                  ),
                ),
              );
            },
            child: const SizedBox(
              width: 180,
              height: 120,
              child: Text('home card'),
            ),
          ),
        ),
        nav: navigator,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(key);
    await tester.pumpAndSettle();
    expect(detailOpens, 1);
    expect(find.text('start watching'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyRepeatEvent(key);
      await tester.pumpAndSettle();
      expect(
        nextOpens,
        0,
        reason: 'Held confirm must not trigger Material Activate on detail',
      );
    }
    await tester.sendKeyUpEvent(key);
    await tester.pumpAndSettle();
    expect(nextOpens, 0);
    expect(await navigator.currentState!.maybePop(), isTrue);
    await tester.pumpAndSettle();
    expect(
      find.text('home card'),
      findsOneWidget,
      reason: 'One BACK after the hold returns home, not to another layer',
    );
    expect(navigator.currentState!.canPop(), isFalse);

    // An actual UP and fresh DOWN are a new activation, not a debounce timer.
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    await tester.pumpAndSettle();
    expect(detailOpens, 2);
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    await tester.pumpAndSettle();
    expect(nextOpens, 1);
    expect(find.text('next route'), findsOneWidget);
  });
  testWidgets('TV guard preserves confirm DOWN UP and directional repeats', (
    tester,
  ) async {
    _cleanup(tester);
    final events = <(LogicalKeyboardKey, Type)>[];
    await tester.pumpWidget(
      _app(
        Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            events.add((event.logicalKey, event.runtimeType));
            return KeyEventResult.handled;
          },
          child: const SizedBox(width: 120, height: 80),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final key in _confirmKeys.take(1)) {
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyRepeatEvent(key);
      await tester.sendKeyUpEvent(key);
      expect(events.where((e) => e.$1 == key).map((e) => e.$2), [
        KeyDownEvent,
        KeyUpEvent,
      ]);
    }
    for (final key in [
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowRight,
    ]) {
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyRepeatEvent(key);
      await tester.sendKeyRepeatEvent(key);
      await tester.sendKeyUpEvent(key);
      expect(events.where((e) => e.$1 == key).map((e) => e.$2), [
        KeyDownEvent,
        KeyRepeatEvent,
        KeyRepeatEvent,
        KeyUpEvent,
      ]);
    }
  });

  testWidgets('non-TV shell retains default Material confirmation repeats', (
    tester,
  ) async {
    _cleanup(tester);
    TvMode.setEnabledForTesting(false);
    var presses = 0;
    await tester.pumpWidget(
      _app(
        TextButton(
          autofocus: true,
          onPressed: () => presses++,
          child: const Text('ordinary button'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(presses, 2);
  });

  testWidgets('disposed shell leaves no global confirm repeat handler', (
    tester,
  ) async {
    _cleanup(tester);
    var initialPresses = 0;
    var afterDisposePresses = 0;
    await tester.pumpWidget(
      _app(
        TextButton(
          autofocus: true,
          onPressed: () => initialPresses++,
          child: const Text('first button'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(initialPresses, 1);
    // Removal must use registration lifetime, not the mode at dispose time.
    TvMode.setEnabledForTesting(false);
    await tester.pumpWidget(
      _app(
        TextButton(
          autofocus: true,
          onPressed: () => afterDisposePresses++,
          child: const Text('button without TV shell'),
        ),
        shell: false,
      ),
    );
    await tester.pumpAndSettle();
    TvMode.setEnabledForTesting(true);
    expect(find.byType(TvAppShell), findsNothing);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      afterDisposePresses,
      1,
      reason: 'Disposed TV guard must not consume replacement tree input',
    );
  });
}
