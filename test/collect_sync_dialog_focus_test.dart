import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/sync_priority.dart';
import 'package:kazumi/modules/collect/collect_sync_plan.dart';
import 'package:kazumi/pages/collect/collect_sync_dialog.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

void main() {
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() => TvMode.setEnabledForTesting(false));
  for (final succeeds in [true, false]) {
    testWidgets('sync result $succeeds retains an actionable remote focus',
        (tester) async {
      final done = Completer<bool>();
      var calls = 0;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      autofocus: true,
                      child: const Text('open'),
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => CollectSyncDialog(
                              plan: const CollectSyncPlan(
                                  webDavEnabled: true,
                                  webDavCollectiblesEnabled: true,
                                  bangumiEnabled: false),
                              priority: BangumiSyncPriority.localFirst,
                              onSync: (step,
                                  {required onError, required onProgress}) {
                                calls++;
                                return done.future;
                              })))))));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      // Route traversal can acquire the first action without pointer input.
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        if (Focus.of(tester.element(find.text('开始同步'))).hasFocus) break;
      }
      expect(Focus.of(tester.element(find.text('开始同步'))).hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls, 1);
      await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(CollectSyncDialog), findsOneWidget);
      done.complete(succeeds);
      await tester.pumpAndSettle();
      final label = succeeds ? '完成' : '关闭';
      expect(find.text(label), findsOneWidget);
      expect(Focus.of(tester.element(find.text(label))).hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(CollectSyncDialog), findsNothing);
    });
  }
}
