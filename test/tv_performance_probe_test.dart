import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/performance/tv_performance_probe.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

List<String> _reportLines(List<String> logs) => logs
    .where((line) => (jsonDecode(line) as Map)['tag'] == 'KAZUMI_TV_PERF')
    .toList();

List<Map<String, dynamic>> _controlMarkers(List<String> logs) => logs
    .map((line) => jsonDecode(line) as Map<String, dynamic>)
    .where((line) => line['tag'] == 'KAZUMI_TV_PERF_CONTROL')
    .toList();

FrameTiming _frame(int number, {int build = 1000, int raster = 2000}) {
  final start = number * 20000;
  return FrameTiming(
    vsyncStart: start,
    buildStart: start + 100,
    buildFinish: start + 100 + build,
    rasterStart: start + 200 + build,
    rasterFinish: start + 200 + build + raster,
    rasterFinishWallTime: 1700000000000000 + start,
    frameNumber: number,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('diagnostic compile flag is off by default', () {
    expect(kazumiTvPerformanceEnabled, isFalse);
    final output = <String>[];
    TvMode.setEnabledForTesting(true);
    try {
      runZoned<void>(TvPerformanceProbe.initialize,
          zoneSpecification:
              ZoneSpecification(print: (_, __, ___, line) => output.add(line)));
    } finally {
      TvMode.setEnabledForTesting(false);
    }
    expect(output, isEmpty,
        reason: 'Flag-off initialization must emit no control markers.');
  });

  test('delayed timing batches exclude old, later and duplicate frames', () {
    var clock = 1000;
    final collector = TvPerformanceCollector(
      runId: 'frame-boundary',
      nowMicros: () => clock,
      mode: 'release',
      refreshRateHz: 60,
      refreshRateSource: 'FlutterView.display',
      startFrameNumber: 100,
      startFocus: 'poster-1',
      startImageCache: {'currentSizeBytes': 100},
    );
    clock = 5000;
    expect(
        collector.addFrames([
          _frame(99),
          _frame(100),
          _frame(101, raster: 20000),
          _frame(-1),
        ]),
        isNull);
    clock = 8000;
    collector.stop(
      reason: 'f10',
      endFrameNumber: 102,
      endFocus: 'poster-2',
      endImageCache: {'currentSizeBytes': 200},
    );
    // A completed-window drain accepts only frames actually in that window.
    clock = 1000000;
    collector.addFrames([_frame(101), _frame(102), _frame(103)]);
    final report = collector.report();
    expect(report['durationUs'], 7000);
    expect(report['summary'], {
      'frames': 2,
      'inputs': 0,
      'build': {'p50Us': 1000, 'p95Us': 1000, 'maxUs': 1000, 'overBudget': 0},
      'raster': {
        'p50Us': 2000,
        'p95Us': 20000,
        'maxUs': 20000,
        'overBudget': 1,
      },
      'totalSpan': {
        'p50Us': 3200,
        'p95Us': 21200,
        'maxUs': 21200,
        'overBudget': 1,
      },
    });
    final boundaries = report['boundaries']! as Map;
    expect(boundaries['excludedOldFrames'], 2);
    expect(boundaries['excludedAfterStopFrames'], 1);
    expect(boundaries['unknownFrameNumbersExcluded'], 1);
    expect(boundaries['duplicateFramesExcluded'], 1);
    final frames = report['frames']! as List;
    expect((frames.first as Map)['reportObservedAtUs'], 4000);
    expect((frames.last as Map)['reportObservedAtUs'], 999000,
        reason: 'Delivery time must remain separate from execution durations.');
  });

  test('input clock excludes early callbacks and labels coalesced focus', () {
    var clock = 0;
    final collector = TvPerformanceCollector(
      runId: 'inputs',
      nowMicros: () => clock,
      mode: 'profile',
      refreshRateHz: 60,
      refreshRateSource: 'fallback_60Hz',
      startFrameNumber: 10,
      startFocus: 'poster-1',
      startImageCache: {},
    );
    clock = 1000;
    collector.addInput(
      key: 'Arrow Right',
      type: 'down',
      receivedFrameNumber: 11,
      observedFocus: 'poster-1',
    );
    clock = 1100;
    collector.addInput(
      key: 'Arrow Right',
      type: 'repeat',
      receivedFrameNumber: 11,
      observedFocus: 'poster-1',
    );
    clock = 1200;
    collector.focusChanged('poster-3', identity: 333);
    clock = 1300;
    collector.submittedFrame(11);
    expect(collector.hasPendingFrameInputs, isTrue);
    clock = 17000;
    collector.submittedFrame(12);
    expect(collector.hasPendingFrameInputs, isFalse);
    clock = 18000;
    collector.addInput(
      key: 'Arrow Right',
      type: 'down',
      receivedFrameNumber: 12,
      observedFocus: 'poster-3',
    );
    collector.addInput(
      key: 'Arrow Left',
      type: 'down',
      receivedFrameNumber: 12,
      observedFocus: 'poster-3',
      synthesized: true,
    );
    clock = 20000;
    collector.stop(
      reason: 'f10',
      endFrameNumber: 12,
      endFocus: 'poster-3',
      endImageCache: {},
    );
    clock = 25000;
    collector.focusChanged('unrelated-late-focus');
    collector.submittedFrame(13);
    final report = collector.report();
    final inputs = report['inputs']! as List;
    expect(inputs.length, 3);
    expect((inputs[0] as Map)['focusStatus'], 'coalesced_before_focus');
    expect((inputs[0] as Map)['inputToPostFrameUs'], 16000);
    expect((inputs[1] as Map)['focusLatencyUs'], 100);
    expect((inputs[1] as Map)['focusIdentity'], 333);
    expect((inputs[1] as Map)['inputToPostFrameUs'], 15900);
    expect((inputs[2] as Map)['frameObservedAtUs'], isNull);
    expect(
        (inputs[2] as Map)['frameStatus'], 'no_later_frame_before_window_end');
    expect((inputs[2] as Map)['focusStatus'],
        'no_focus_observed_before_window_end');
    final boundaries = report['boundaries']! as Map;
    expect(boundaries['earlyPostFrameCallbacksExcluded'], 1);
    expect(boundaries['synthesizedInputsExcluded'], 1);
    expect(boundaries['inputsWithoutFocus'], 2);
    expect(boundaries['inputsWithoutLaterFrame'], 1);
    expect((report['focusEvents']! as List).length, 1);
  });

  test('duration, frame and input caps are finite and reporting is end-only',
      () {
    var clock = 0;
    TvPerformanceCollector make(String id) => TvPerformanceCollector(
          runId: id,
          nowMicros: () => clock,
          mode: 'release',
          refreshRateHz: 50,
          refreshRateSource: 'FlutterView.display',
          startFrameNumber: 0,
          startFocus: null,
          startImageCache: {},
          maxFrames: 2,
          maxInputs: 2,
          maxDuration: const Duration(seconds: 1),
        );
    final frames = make('frames');
    expect(frames.report, throwsStateError);
    expect(frames.addFrames([_frame(1), _frame(2), _frame(3)]), 'frame_limit');
    expect(frames.frameCount, 2);
    final inputs = make('inputs');
    for (var index = 0; index < 3; index++) {
      final bound = inputs.addInput(
        key: 'Arrow Down',
        type: 'down',
        receivedFrameNumber: 0,
        observedFocus: null,
      );
      expect(bound, index == 0 ? isNull : 'input_limit');
    }
    expect(inputs.inputCount, 2);
    clock = 999999;
    expect(inputs.expired, isFalse);
    clock = 1000000;
    expect(inputs.expired, isTrue);
    inputs.stop(
      reason: 'timeout',
      endFrameNumber: 3,
      endFocus: null,
      endImageCache: {},
    );
    expect(inputs.report()['endReason'], 'timeout');
    expect(
        inputs.addInput(
            key: 'Arrow Down',
            type: 'down',
            receivedFrameNumber: 4,
            observedFocus: null),
        isNull);
    expect(inputs.inputCount, 2);
  });

  test('log chunks have run identity and losslessly preserve Unicode JSON', () {
    final report = <String, Object?>{
      'runId': 'test-123',
      'focus': List.filled(1000, '电视焦点😀\\"\n').join(),
    };
    final lines = TvPerformanceProbe.encodeLogChunks(report);
    expect(lines.length, greaterThan(1));
    final joined = StringBuffer();
    for (var index = 0; index < lines.length; index++) {
      expect(lines[index].length, lessThanOrEqualTo(900));
      expect(utf8.encode(lines[index]).length, lessThanOrEqualTo(900));
      expect(lines[index].contains('\n'), isFalse);
      expect(lines[index].codeUnits.every((unit) => unit <= 0x7f), isTrue);
      final envelope = jsonDecode(lines[index]) as Map;
      expect(envelope['tag'], 'KAZUMI_TV_PERF');
      expect(envelope['runId'], 'test-123');
      expect(envelope['part'], index + 1);
      expect(envelope['total'], lines.length);
      joined.write(envelope['payload']);
    }
    expect(jsonDecode(joined.toString()), report);
  });

  test('worst-case envelope escaping stays below the real TV line limit', () {
    final report = <String, Object?>{
      'runId': '1234567890123456-123456789',
      'backslashes': List.filled(4000, '\\').join(),
      'quotes': List.filled(4000, '"').join(),
      'unicode': List.filled(1000, '电视😀').join(),
    };
    final lines = TvPerformanceProbe.encodeLogChunks(report);
    final joined = StringBuffer();
    for (final line in lines) {
      expect(utf8.encode(line).length, lessThanOrEqualTo(900));
      expect(line.codeUnits.every((unit) => unit <= 0x7f), isTrue);
      final envelope = jsonDecode(line) as Map;
      joined.write(envelope['payload']);
    }
    expect(lines.any((line) => line.length > 750), isTrue,
        reason: 'Exercise payloads close to maximum double-escaping overhead.');
    expect(jsonDecode(joined.toString()), report);
  });

  test('a delayed deadline observation is reported explicitly', () {
    var clock = 0;
    final collector = TvPerformanceCollector(
      runId: 'delayed-timeout',
      nowMicros: () => clock,
      mode: 'release',
      refreshRateHz: 60,
      refreshRateSource: 'fallback_60Hz',
      startFrameNumber: 0,
      startFocus: null,
      startImageCache: {},
    );
    clock = 60005000;
    collector.stop(
      reason: 'timeout',
      endFrameNumber: 1,
      endFocus: null,
      endImageCache: {},
    );
    final report = collector.report();
    expect((report['boundaries']! as Map)['deadlineCallbackLateUs'], 5000);
    expect(report['durationUs'], 60005000,
        reason: 'A blocked isolate cannot promise an exact wall-clock timer.');
  });

  testWidgets('flag-off and non-TV probes leave F9 and ordinary input alone',
      (tester) async {
    for (final settings in [(false, true), (true, false)]) {
      final logs = <String>[];
      final probe = TvPerformanceProbe.testing(
        enabled: settings.$1,
        television: settings.$2,
        onLog: logs.add,
        nowMicros: () => 0,
      )..install();
      expect(probe.installed, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(probe.sampling, isFalse);
      expect(logs, isEmpty);
      probe.dispose();
    }
  });

  testWidgets('ordinary focus navigation is passive and logs only after F10',
      (tester) async {
    final first = FocusNode(debugLabel: 'first');
    final second = FocusNode(debugLabel: 'second');
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Row(children: [
        Focus(focusNode: first, child: const Text('one')),
        Focus(focusNode: second, child: const Text('two')),
      ]),
    ));
    first.requestFocus();
    await tester.pump();
    var clock = 0;
    final logs = <String>[];
    final probe = TvPerformanceProbe.testing(
      enabled: true,
      television: true,
      onLog: logs.add,
      nowMicros: () => clock,
      drainDuration: const Duration(milliseconds: 20),
    )..install();
    addTearDown(probe.dispose);
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    expect(probe.sampling, isTrue);
    clock = 1000;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(second.hasFocus, isTrue);
    expect(_reportLines(logs), isEmpty);
    // A second F9 must not discard or restart the already-open window.
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    expect(probe.sampling, isTrue);
    clock = 2000;
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    expect(probe.sampling, isFalse);
    expect(_reportLines(logs), isEmpty);
    await tester.pump(const Duration(milliseconds: 20));
    expect(logs, isNotEmpty);
    final payload = _reportLines(logs)
        .map((line) => (jsonDecode(line) as Map)['payload']! as String)
        .join();
    final report = jsonDecode(payload) as Map;
    expect(report['endReason'], 'f10');
    expect((report['inputs'] as List).length, 1);
    expect((report['imageCacheStart'] as Map).containsKey('pendingImageCount'),
        isTrue);
  });

  testWidgets('an idle diagnostic window ends once at its 60-second bound',
      (tester) async {
    var clock = 0;
    final logs = <String>[];
    final probe = TvPerformanceProbe.testing(
      enabled: true,
      television: true,
      onLog: logs.add,
      nowMicros: () => clock,
      drainDuration: const Duration(milliseconds: 20),
    )..install();
    addTearDown(probe.dispose);
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pump(const Duration(seconds: 59));
    expect(probe.sampling, isTrue);
    expect(_reportLines(logs), isEmpty);
    clock = 60000000;
    await tester.pump(const Duration(seconds: 1));
    expect(probe.sampling, isFalse);
    expect(_reportLines(logs), isEmpty);
    await tester.pump(const Duration(milliseconds: 20));
    final count = logs.length;
    expect(count, greaterThan(0));
    final payload = _reportLines(logs)
        .map((line) => (jsonDecode(line) as Map)['payload']! as String)
        .join();
    expect((jsonDecode(payload) as Map)['endReason'], 'timeout');
    await tester.pump(const Duration(seconds: 61));
    expect(logs.length, count, reason: 'No automatic repeat windows.');
    expect(probe.sampling, isFalse);
  });

  testWidgets('control markers are limited independently of idle key markers',
      (tester) async {
    final logs = <String>[];
    final probe = TvPerformanceProbe.testing(
      enabled: true,
      television: true,
      onLog: logs.add,
      nowMicros: () => 0,
      drainDuration: const Duration(milliseconds: 20),
    )..install();
    addTearDown(probe.dispose);
    probe.install();
    var markers = _controlMarkers(logs);
    expect(markers.length, 1);
    expect(markers.single['event'], 'install');
    final keyboardIdentity = markers.single['hardwareKeyboardIdentity'];
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(_controlMarkers(logs).length, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    markers = _controlMarkers(logs);
    final controls =
        markers.where((marker) => marker['event'] == 'control_key');
    expect(controls.length, 4);
    expect(controls.map((marker) => marker['control']),
        ['F9', 'F9', 'F10', 'F10']);
    expect(
        controls.map((marker) => marker['type']), ['down', 'up', 'down', 'up']);
    for (final marker in controls) {
      expect(marker['synthesized'], isFalse);
      expect(marker['hardwareKeyboardIdentity'], keyboardIdentity);
      expect(marker['registeredKeyboardIdentity'], keyboardIdentity);
      expect(marker['logicalKeyId'], isA<int>());
      expect(marker['physicalKeyId'], isA<int>());
    }
    // Additional control presses can act, but may not flood marker logs.
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(
        _controlMarkers(logs)
            .where((marker) => marker['event'] == 'control_key')
            .length,
        4);
    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('idle input mapping has a lifetime cap and is silent in a window',
      (tester) async {
    final logs = <String>[];
    final probe = TvPerformanceProbe.testing(
      enabled: true,
      television: true,
      onLog: logs.add,
      nowMicros: () => 0,
      drainDuration: const Duration(milliseconds: 20),
    )..install();
    addTearDown(probe.dispose);
    for (final key in [
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowRight,
    ]) {
      await tester.sendKeyEvent(key);
    }
    List<Map<String, dynamic>> idleKeys() => _controlMarkers(logs)
        .where((marker) => marker['event'] == 'idle_key')
        .toList();
    expect(idleKeys().length, 4);
    expect(idleKeys().map((marker) => marker['logicalKeyId']), [
      LogicalKeyboardKey.arrowRight.keyId,
      LogicalKeyboardKey.arrowLeft.keyId,
      LogicalKeyboardKey.arrowDown.keyId,
      LogicalKeyboardKey.arrowUp.keyId,
    ]);
    expect(idleKeys().every((marker) => marker['sampling'] == false), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    expect(probe.sampling, isTrue);
    final beforeOrdinaryKey = logs.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(logs.length, beforeOrdinaryKey,
        reason: 'Ordinary window input must not emit markers or frame logs.');
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(idleKeys().length, 4);
    await tester.pump(const Duration(milliseconds: 20));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(idleKeys().length, 4,
        reason: 'Starting or ending a window must not reset the lifetime cap.');
  });

  testWidgets('F10 toggles windows, ignores drain, and can start the next run',
      (tester) async {
    var clock = 0;
    final logs = <String>[];
    final probe = TvPerformanceProbe.testing(
      enabled: true,
      television: true,
      onLog: logs.add,
      nowMicros: () => clock,
      drainDuration: const Duration(milliseconds: 20),
    )..install();
    addTearDown(probe.dispose);
    expect(probe.sampling, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    expect(probe.sampling, isTrue);
    clock = 1000;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    clock = 2000;
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    expect(probe.sampling, isFalse);
    expect(_reportLines(logs), isEmpty);
    // Closing a window must not let another F10 discard its delayed timings.
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    expect(probe.sampling, isFalse);
    await tester.pump(const Duration(milliseconds: 20));
    final firstEnvelopes =
        _reportLines(logs).map((line) => jsonDecode(line) as Map).toList();
    expect(firstEnvelopes.map((part) => part['runId']).toSet().length, 1);
    final firstReport = jsonDecode(
        firstEnvelopes.map((part) => part['payload']! as String).join()) as Map;
    expect(firstReport['endReason'], 'f10');
    expect(firstReport['durationUs'], 2000);
    expect((firstReport['inputs'] as List).length, 1);
    final previousReportLines = _reportLines(logs).length;
    clock = 3000;
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    expect(probe.sampling, isTrue);
    clock = 4000;
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    expect(probe.sampling, isFalse);
    await tester.pump(const Duration(milliseconds: 20));
    final secondEnvelopes = _reportLines(logs)
        .skip(previousReportLines)
        .map((line) => jsonDecode(line) as Map)
        .toList();
    final secondReport = jsonDecode(
            secondEnvelopes.map((part) => part['payload']! as String).join())
        as Map;
    expect(secondReport['runId'], isNot(firstReport['runId']));
    expect(secondReport['endReason'], 'f10');
    expect(secondReport['durationUs'], 1000);
    expect((secondReport['inputs'] as List), isEmpty);
  });
}
