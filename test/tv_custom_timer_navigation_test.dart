import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/dialog/dialog.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/player/timed_shutdown_service.dart';

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, {bool tv = true}) async {
  TvMode.setEnabledForTesting(tv);
  await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      navigatorObservers: [KazumiDialog.observer],
      home: Scaffold(
          body: TextButton(
              autofocus: true,
              onPressed: TimedShutdownService.showCustomTimerDialog,
              child: const Text('open')))));
  await tester.pumpAndSettle();
  await _key(tester, LogicalKeyboardKey.enter);
}

double _value(WidgetTester tester, int index) =>
    tester.widget<Slider>(find.byType(Slider).at(index)).value;

void main() {
  setUp(() => TimedShutdownService().cancel());
  tearDown(() {
    TimedShutdownService().cancel();
    TvMode.setEnabledForTesting(false);
  });
  testWidgets(
      'TV custom timer boundaries and vertical traversal do not start timer; cancel',
      (tester) async {
    await _open(tester);
    expect(find.byType(Slider), findsNWidgets(2));
    expect(find.byType(CupertinoPicker), findsNothing);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.arrowLeft);
    expect(_value(tester, 0), 0);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(_value(tester, 0), 1);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(_value(tester, 0), 1);
    expect(_value(tester, 1), 0);
    await _key(tester, LogicalKeyboardKey.arrowLeft);
    expect(_value(tester, 1), 0);
    for (var i = 0; i < 62; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    expect(_value(tester, 1), 59);
    await _key(tester, LogicalKeyboardKey.arrowUp);
    for (var i = 0; i < 26; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    expect(_value(tester, 0), 24);
    expect(_value(tester, 1), 59);
    expect(TimedShutdownService().isActive, isFalse);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.enter);
    expect(find.byType(AlertDialog), findsNothing);
    expect(TimedShutdownService().isActive, isFalse);
  });
  testWidgets('TV zero stays open then corrected 61 minutes confirms',
      (tester) async {
    await _open(tester);
    expect(find.byType(Slider), findsNWidgets(2));
    for (var i = 0; i < 3; i++) {
      await _key(tester, LogicalKeyboardKey.arrowDown);
    }
    await _key(tester, LogicalKeyboardKey.arrowRight);
    await _key(tester, LogicalKeyboardKey.enter);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(TimedShutdownService().isActive, isFalse);
    await _key(tester, LogicalKeyboardKey.arrowUp);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(_value(tester, 1), 1);
    await _key(tester, LogicalKeyboardKey.arrowUp);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(_value(tester, 0), 1);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    await _key(tester, LogicalKeyboardKey.enter);
    expect(find.byType(AlertDialog), findsNothing);
    expect(TimedShutdownService().isActive, isTrue);
    expect(TimedShutdownService().setMinutes, 61);
    TimedShutdownService().cancel();
  });
  testWidgets('non TV retains both native pickers and cancellation',
      (tester) async {
    await _open(tester, tv: false);
    expect(find.byType(CupertinoPicker), findsNWidgets(2));
    expect(find.byType(Slider), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(TimedShutdownService().isActive, isFalse);
  });
}
