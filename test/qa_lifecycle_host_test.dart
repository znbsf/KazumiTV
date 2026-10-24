import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tools/qa/source_batch/lifecycle_gate.dart';
import '../tools/qa/source_batch/lifecycle_host.dart';

class _PendingPage extends StatefulWidget {
  const _PendingPage(this.ticket, this.done, this.finish, this.disposed,
      {super.key});
  final QaCaseTicket ticket;
  final Completer<Map<String, dynamic>> done;
  final void Function(Map<String, dynamic>) finish;
  final VoidCallback disposed;
  @override
  State<_PendingPage> createState() => _PendingState();
}

class _PendingState extends State<_PendingPage> {
  @override
  void initState() {
    super.initState();
    widget.ticket.attachCancel(() {});
    widget.done.future.then(widget.finish);
  }

  @override
  void dispose() {
    widget.ticket.cancel();
    widget.disposed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(body: Text(widget.ticket.id));
}

void main() {
  const channel = MethodChannel('qa/lifecycle-host-test');
  for (final action in ['exit', 'switch', 'switch-key', 'unclean', 'normal']) {
    testWidgets('actual QA page $action binds results and waits for retirement',
        (tester) async {
      var nativeGeneration = 0;
      String? nativeId;
      final writes = <Map<String, dynamic>>[];
      var rejected = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        if (call.method == 'qaBegin') {
          final a = Map<String, dynamic>.from(call.arguments as Map);
          if ((a['generation'] as int) <= nativeGeneration) {
            throw StateError('Native generation must increase');
          }
          nativeGeneration = a['generation'] as int;
          nativeId = a['case_id'] as String;
        } else if (call.method == 'qaInvalidate') {
          nativeId = null;
        } else if (call.method == 'result') {
          final r = Map<String, dynamic>.from(
              jsonDecode(call.arguments as String) as Map);
          if (r['qa_generation'] != nativeGeneration ||
              r['qa_case_id'] != nativeId) {
            rejected++;
            return false;
          }
          writes.add(r);
          return true;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      final done = <String, Completer<Map<String, dynamic>>>{
        'old': Completer(),
        'next': Completer()
      };
      final tickets = <String, QaCaseTicket>{};
      final callbacks = <String, void Function(Map<String, dynamic>)>{};
      final signals = <String, void Function(Map<String, Object?>)>{};
      final pageFocus = FocusNode(debugLabel: 'fixture-page-stole-focus');
      addTearDown(pageFocus.dispose);
      final started = <String>[];
      final config = <String, dynamic>{'id': 'old'};
      if (action != 'normal') {
        config['qa_lifecycle'] = {
          'action': action == 'exit' ? 'exit' : 'switch',
          'trigger_phase': 'primary',
          'target': {'id': 'next', 'url': 'http://127.0.0.1:8769/video-next'}
        };
      }
      await tester.pumpWidget(MaterialApp(
          home: QaLifecycleHost(
              config: config,
              channel: channel,
              pageBuilder: (c, ticket, finished, signal, disposed) {
                if (!tickets.containsKey(ticket.id)) started.add(ticket.id);
                tickets[ticket.id] = ticket;
                callbacks[ticket.id] = finished;
                signals[ticket.id] = signal;
                return Focus(
                    focusNode: ticket.id == 'old' ? pageFocus : null,
                    child: _PendingPage(
                        ticket, done[ticket.id]!, finished, disposed,
                        key: ValueKey(ticket.generation)));
              })));
      await tester.pumpAndSettle();
      if (action == 'normal') {
        expect(find.text('Switch QA fixture'), findsNothing);
        done['old']!.complete(
            {'id': 'old', 'stage': 'first_frame', 'cleanup': 'confirmed'});
        await tester.pumpAndSettle();
        expect(writes.single['qa_case_id'], 'old');
        expect(rejected, 0);
        return;
      }
      if (action == 'exit') {
        await tester.binding.handlePopRoute();
      } else if (action == 'switch-key') {
        pageFocus.requestFocus();
        await tester.pump();
        signals['old']!({'phase': 'primary', 'stage': 'started'});
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
      } else {
        await tester.tap(find.text('Switch QA fixture'));
      }
      await tester.pumpAndSettle();
      expect(tickets['old']!.cancelled, true);
      expect(find.text('old'), findsNothing);
      expect(started, ['old']);
      done['old']!.complete({
        'id': 'old',
        'stage': 'first_frame',
        'media_identity': 'OLD_LATE',
        'cleanup': action == 'unclean' ? 'unconfirmed' : 'confirmed'
      });
      await tester.pumpAndSettle();
      if (action == 'switch' || action == 'switch-key') {
        expect(started, ['old', 'next']);
        expect(writes, isEmpty);
        callbacks['old']!(
            {'id': 'old', 'stage': 'first_frame', 'cleanup': 'confirmed'});
        done['next']!.complete(
            {'id': 'next', 'stage': 'first_frame', 'cleanup': 'confirmed'});
        await tester.pumpAndSettle();
        expect(writes.single['qa_case_id'], 'next');
      } else {
        expect(started, ['old']);
        expect(
            writes.single['stage'],
            action == 'exit'
                ? 'lifecycle_cancelled'
                : 'lifecycle_cleanup_unconfirmed');
      }
      expect(rejected, 1);
      final children = (writes.single['lifecycle'] as Map)['children'] as List;
      expect(children.first['normal_publication_allowed'], false);
      expect((writes.single['lifecycle'] as Map)['actual_page_disposals'], 1);
      expect(tester.takeException(), isNull);
    });
  }
}
