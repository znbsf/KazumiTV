import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/controller/player_debug_controller.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mobx/mobx.dart';

class _CountingLog extends PlayerLog {
  _CountingLog(String text) : super(prefix: 'test', level: 'info', text: text);

  int formatCalls = 0;

  @override
  String toString() {
    formatCalls++;
    return super.toString();
  }
}

void main() {
  test('unopened raw logs bound total payload and clear resets accounting', () {
    final controller = PlayerDebugController();
    for (var i = 0; i < 600; i++) {
      controller.recordLog(_CountingLog('$i ${'字' * 5000}'),
          playerDebugMode: false);
      expect(
          controller.retainedRawLogCharacters, lessThanOrEqualTo(256 * 1024));
      expect(controller.retainedRawLogCount, lessThanOrEqualTo(500));
    }
    expect(controller.retainedRawLogCount, 64);
    expect(controller.retainedRawLogCharacters, 256 * 1024);
    expect(controller.playerLog, isEmpty);
    controller.attachLogViewer();
    expect(controller.playerLog.last, contains('599 '));
    expect(controller.playerLog.last, contains('truncated'));
    controller.detachLogViewer();
    controller.clearLogs();
    expect(controller.retainedRawLogCharacters, 0);
    expect(controller.retainedRawLogCount, 0);
    controller.recordLog(_CountingLog('short'), playerDebugMode: false);
    expect(controller.retainedRawLogCharacters, 'testinfoshort'.length);
    expect(controller.retainedRawLogCount, 1);
  });

  test('oversized prefix and level cannot bypass raw payload bounds', () {
    final controller = PlayerDebugController();
    controller.recordLog(
      PlayerLog(prefix: 'p' * 100000, level: 'l' * 100000, text: 't' * 100000),
      playerDebugMode: false,
    );
    expect(controller.retainedRawLogCharacters, 4096);
    expect(controller.retainedRawLogCount, 1);
    expect(controller.playerLog, isEmpty);
    controller.attachLogViewer();
    expect(controller.playerLog.single, contains('truncated'));
    controller.detachLogViewer();
  });

  test('debug off retains raw logs and formats only for attached viewers', () {
    final controller = PlayerDebugController();
    final retained = _CountingLog('retained');
    var notifications = 0;
    final stop = autorun((_) {
      controller.playerLog.length;
      notifications++;
    });
    addTearDown(stop.call);

    controller.recordLog(retained, playerDebugMode: false);
    expect(retained.formatCalls, 0);
    expect(controller.playerLog, isEmpty);
    expect(notifications, 1);

    controller.attachLogViewer();
    expect(retained.formatCalls, 1);
    expect(controller.playerLog.single, contains('retained'));
    controller.attachLogViewer();
    expect(retained.formatCalls, 1);
    expect(controller.playerLog.length, 1);

    final live = _CountingLog('live');
    controller.recordLog(live, playerDebugMode: false);
    expect(live.formatCalls, 1);
    expect(controller.playerLog.last, contains('live'));
    controller.detachLogViewer();
    final shared = _CountingLog('remaining viewer');
    controller.recordLog(shared, playerDebugMode: false);
    expect(shared.formatCalls, 1);

    controller.detachLogViewer();
    final beforeDetach = controller.playerLog.toList();
    final beforeNotifications = notifications;
    final deferred = _CountingLog('deferred');
    controller.recordLog(deferred, playerDebugMode: false);
    expect(deferred.formatCalls, 0);
    expect(controller.playerLog, beforeDetach);
    expect(notifications, beforeNotifications);

    controller.attachLogViewer();
    expect(deferred.formatCalls, 1);
    expect(controller.playerLog.length, 4);
    expect(controller.playerLog.last, contains('deferred'));
    controller.detachLogViewer();
  });

  test('raw logs retain only the latest 500 events without formatting', () {
    final controller = PlayerDebugController();
    final events = List.generate(600, (i) => _CountingLog('event $i'));
    for (final event in events) {
      controller.recordLog(event, playerDebugMode: false);
    }
    expect(events.every((event) => event.formatCalls == 0), isTrue);
    controller.attachLogViewer();
    expect(controller.playerLog.length, 500);
    expect(controller.playerLog.first, contains('event 100)'));
    expect(controller.playerLog.last, contains('event 599)'));
    expect(events.take(100).every((event) => event.formatCalls == 0), isTrue);
    controller.detachLogViewer();
  });

  test('materializing raw logs respects the formatted size limits', () {
    final controller = PlayerDebugController();
    for (var i = 0; i < 600; i++) {
      controller.recordLog(_CountingLog('$i ${'字' * 5000}'),
          playerDebugMode: false);
    }
    controller.attachLogViewer();
    expect(controller.playerLog.length, lessThanOrEqualTo(500));
    expect(controller.playerLog.fold<int>(0, (n, line) => n + line.length),
        lessThanOrEqualTo(256 * 1024));
    expect(controller.playerLog.last, contains('599 '));
    controller.detachLogViewer();
  });

  test('clearLogs clears both stores and preserves viewer attachment', () {
    final controller = PlayerDebugController();
    controller.recordLog(_CountingLog('old player'), playerDebugMode: false);
    controller.attachLogViewer();
    controller.clearLogs();
    expect(controller.playerLog, isEmpty);
    final current = _CountingLog('new player');
    controller.recordLog(current, playerDebugMode: false);
    expect(current.formatCalls, 1);
    expect(controller.playerLog.single, contains('new player'));
    controller.detachLogViewer();
    controller.clearLogs();
    controller.attachLogViewer();
    expect(controller.playerLog, isEmpty);
    controller.detachLogViewer();
  });
}
