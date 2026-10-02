import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FramePhase;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

/// Opt-in only. An ordinary build installs no probe listeners or timers.
const bool kazumiTvPerformanceEnabled =
    bool.fromEnvironment('KAZUMI_TV_PERF', defaultValue: false);

/// Bounded in-memory collector. Flutter frame durations and Dart's monotonic
/// input clock remain separate; their raw timestamp epochs are never compared.
class TvPerformanceCollector {
  TvPerformanceCollector({
    required this.runId,
    required this.nowMicros,
    required this.mode,
    required this.refreshRateHz,
    required this.refreshRateSource,
    required this.startFrameNumber,
    required String? startFocus,
    required Map<String, int> startImageCache,
    int? startFocusIdentity,
    this.maxFrames = 1800,
    this.maxInputs = 256,
    this.maxDuration = const Duration(seconds: 60),
  })  : assert(maxFrames > 0 && maxFrames <= 1800),
        assert(maxInputs > 0 && maxInputs <= 256),
        assert(maxDuration > Duration.zero &&
            maxDuration <= const Duration(seconds: 60)),
        assert(refreshRateHz > 0),
        startedAtUs = nowMicros(),
        _startFocus = startFocus,
        _startFocusIdentity = startFocusIdentity,
        _startImageCache = Map.of(startImageCache);

  final String runId;
  final int Function() nowMicros;
  final String mode;
  final double refreshRateHz;
  final String refreshRateSource;
  final int startFrameNumber;
  final int maxFrames;
  final int maxInputs;
  final Duration maxDuration;
  final int startedAtUs;
  final String? _startFocus;
  final int? _startFocusIdentity;
  final Map<String, int> _startImageCache;
  final List<Map<String, Object?>> _frames = [];
  final List<Map<String, Object?>> _inputs = [];
  final List<Map<String, Object?>> _focusEvents = [];
  final List<int> _awaitingFocus = [];
  final Set<int> _frameNumbers = {};
  int? _endedAtUs;
  int? _endFrameNumber;
  String? _endReason;
  String? _endFocus;
  int? _endFocusIdentity;
  Map<String, int>? _endImageCache;
  int _excludedOldFrames = 0;
  int _excludedAfterStopFrames = 0;
  int _unknownFrameNumbers = 0;
  int _duplicateFrames = 0;
  int _droppedFramesAtLimit = 0;
  int _droppedFocusEvents = 0;
  int _earlyPostFrameCallbacks = 0;
  int _syntheticInputs = 0;

  bool get isOpen => _endedAtUs == null;
  bool get expired => nowMicros() - startedAtUs >= maxDuration.inMicroseconds;
  bool get hasPendingFrameInputs => _inputs.any((input) =>
      input['frameObservedAtUs'] == null && input['frameStatus'] == 'pending');
  int get frameCount => _frames.length;
  int get inputCount => _inputs.length;
  int get relativeNowUs => nowMicros() - startedAtUs;

  /// Returns the bound that requires the adapter to close the window.
  String? addFrames(List<FrameTiming> timings) {
    for (final timing in timings) {
      final number = timing.frameNumber;
      if (number < 0) {
        _unknownFrameNumbers++;
        continue;
      }
      if (number <= startFrameNumber) {
        _excludedOldFrames++;
        continue;
      }
      if (_endFrameNumber != null && number > _endFrameNumber!) {
        _excludedAfterStopFrames++;
        continue;
      }
      if (_frameNumbers.contains(number)) {
        _duplicateFrames++;
        continue;
      }
      if (_frames.length >= maxFrames) {
        _droppedFramesAtLimit++;
        continue;
      }
      _frameNumbers.add(number);
      final build = timing.buildDuration.inMicroseconds;
      final raster = timing.rasterDuration.inMicroseconds;
      final total = timing.totalSpan.inMicroseconds;
      final budget = 1000000 / refreshRateHz;
      _frames.add({
        'frame': number,
        // Engine timestamps, never delivery time. Wall raster finish allows
        // coarse alignment to external system-clock resource samples without
        // equating the Dart Stopwatch epoch with Android uptime.
        'vsyncStartUs': timing.timestampInMicroseconds(FramePhase.vsyncStart),
        'buildStartUs': timing.timestampInMicroseconds(FramePhase.buildStart),
        'rasterStartUs': timing.timestampInMicroseconds(FramePhase.rasterStart),
        'rasterFinishUs':
            timing.timestampInMicroseconds(FramePhase.rasterFinish),
        'rasterFinishWallUs':
            timing.timestampInMicroseconds(FramePhase.rasterFinishWallTime),
        'rasterCacheLayerBytes': timing.layerCacheBytes,
        'rasterCachePictureBytes': timing.pictureCacheBytes,
        'buildUs': build,
        'rasterUs': raster,
        'totalSpanUs': total,
        'vsyncOverheadUs': timing.vsyncOverhead.inMicroseconds,
        'buildOverBudget': build > budget,
        'rasterOverBudget': raster > budget,
        'totalOverBudget': total > budget,
        'reportObservedAtUs': relativeNowUs,
      });
    }
    return isOpen && _frames.length >= maxFrames ? 'frame_limit' : null;
  }

  /// Only down/repeat events enter this collector; key-up is not a new input.
  String? addInput({
    required String key,
    required String type,
    required int receivedFrameNumber,
    required String? observedFocus,
    int? observedFocusIdentity,
    bool synthesized = false,
  }) {
    if (!isOpen) return null;
    if (synthesized) {
      _syntheticInputs++;
      return null;
    }
    if (_inputs.length >= maxInputs) return 'input_limit';
    final sequence = _inputs.length + 1;
    _inputs.add({
      'seq': sequence,
      'key': key,
      'type': type,
      'receivedAtUs': relativeNowUs,
      'receivedFrame': receivedFrameNumber,
      'observedFocusAtHandler': observedFocus,
      'observedFocusIdentityAtHandler': observedFocusIdentity,
      'focusObservedAtUs': null,
      'focusLatencyUs': null,
      'focusLabel': null,
      'focusIdentity': null,
      'focusStatus': 'pending',
      'frameObservedAtUs': null,
      'inputToPostFrameUs': null,
      'submittedFrame': null,
      'frameStatus': 'pending',
    });
    _awaitingFocus.add(sequence - 1);
    return _inputs.length >= maxInputs ? 'input_limit' : null;
  }

  void focusChanged(String? label, {int? identity}) {
    if (!isOpen) return;
    final observedAt = relativeNowUs;
    int? latestSequence;
    final coalesced = <int>[];
    if (_awaitingFocus.isNotEmpty) {
      final latest = _awaitingFocus.last;
      latestSequence = latest + 1;
      for (final earlier in _awaitingFocus.take(_awaitingFocus.length - 1)) {
        _inputs[earlier]['focusStatus'] = 'coalesced_before_focus';
        coalesced.add(earlier + 1);
      }
      final input = _inputs[latest];
      input['focusObservedAtUs'] = observedAt;
      input['focusLatencyUs'] = observedAt - (input['receivedAtUs']! as int);
      input['focusLabel'] = label;
      input['focusIdentity'] = identity;
      input['focusStatus'] = 'observed_after_key_not_proven_causal';
      _awaitingFocus.clear();
    }
    if (_focusEvents.length >= 512) {
      _droppedFocusEvents++;
      return;
    }
    _focusEvents.add({
      'observedAtUs': observedAt,
      'label': label,
      'identity': identity,
      'latestInputSeq': latestSequence,
      'coalescedInputSeqs': coalesced,
    });
  }

  /// Called after framework render submission. A callback in the input's
  /// already-running frame is excluded, rather than producing an early sample.
  void submittedFrame(int frameNumber) {
    if (!isOpen) return;
    final observedAt = relativeNowUs;
    var excludedEarly = false;
    for (final input in _inputs) {
      if (input['frameStatus'] != 'pending') continue;
      if (frameNumber <= (input['receivedFrame']! as int)) {
        excludedEarly = true;
        continue;
      }
      input['frameObservedAtUs'] = observedAt;
      input['inputToPostFrameUs'] =
          observedAt - (input['receivedAtUs']! as int);
      input['submittedFrame'] = frameNumber;
      input['frameStatus'] = 'first_later_framework_post_frame';
    }
    if (excludedEarly) _earlyPostFrameCallbacks++;
  }

  void stop({
    required String reason,
    required int endFrameNumber,
    required String? endFocus,
    required Map<String, int> endImageCache,
    int? endFocusIdentity,
  }) {
    if (!isOpen) return;
    _endedAtUs = nowMicros();
    _endFrameNumber = endFrameNumber;
    _endReason = reason;
    _endFocus = endFocus;
    _endFocusIdentity = endFocusIdentity;
    _endImageCache = Map.of(endImageCache);
    for (final input in _inputs) {
      if (input['focusStatus'] == 'pending') {
        input['focusStatus'] = 'no_focus_observed_before_window_end';
      }
      if (input['frameStatus'] == 'pending') {
        input['frameStatus'] = 'no_later_frame_before_window_end';
      }
    }
    _awaitingFocus.clear();
  }

  Map<String, Object?> report() {
    if (isOpen) throw StateError('Only completed windows can be reported.');
    final budget = 1000000 / refreshRateHz;
    return {
      'schema': 1,
      'runId': runId,
      'mode': mode,
      'durationUs': _endedAtUs! - startedAtUs,
      'endReason': _endReason,
      'refreshRateHz': refreshRateHz,
      'refreshRateSource': refreshRateSource,
      'frameBudgetUs': budget,
      'startFrame': startFrameNumber,
      'endFrame': _endFrameNumber,
      'limits': {
        'maxDurationUs': maxDuration.inMicroseconds,
        'maxFrames': maxFrames,
        'maxInputs': maxInputs,
        'maxFocusEvents': 512,
      },
      'summary': {
        'frames': _frames.length,
        'inputs': _inputs.length,
        'build': _durationSummary('buildUs', budget),
        'raster': _durationSummary('rasterUs', budget),
        'totalSpan': _durationSummary('totalSpanUs', budget),
      },
      'boundaries': {
        'excludedOldFrames': _excludedOldFrames,
        'excludedAfterStopFrames': _excludedAfterStopFrames,
        'unknownFrameNumbersExcluded': _unknownFrameNumbers,
        'duplicateFramesExcluded': _duplicateFrames,
        'droppedFramesAtLimit': _droppedFramesAtLimit,
        'droppedFocusEventsAtLimit': _droppedFocusEvents,
        'earlyPostFrameCallbacksExcluded': _earlyPostFrameCallbacks,
        'synthesizedInputsExcluded': _syntheticInputs,
        'deadlineCallbackLateUs': _endReason == 'timeout' &&
                _endedAtUs! - startedAtUs > maxDuration.inMicroseconds
            ? _endedAtUs! - startedAtUs - maxDuration.inMicroseconds
            : 0,
        'inputsWithoutFocus':
            _inputs.where((input) => input['focusObservedAtUs'] == null).length,
        'inputsWithoutLaterFrame':
            _inputs.where((input) => input['frameObservedAtUs'] == null).length,
        'inputsWithSubmittedFrameOutsideTimingSample': _inputs
            .where((input) =>
                input['submittedFrame'] != null &&
                !_frameNumbers.contains(input['submittedFrame']))
            .length,
        'focusEventsWithoutPendingInput': _focusEvents
            .where((event) => event['latestInputSeq'] == null)
            .length,
      },
      'focusStart': _startFocus,
      'focusEnd': _endFocus,
      'focusIdentityStart': _startFocusIdentity,
      'focusIdentityEnd': _endFocusIdentity,
      'imageCacheStart': _startImageCache,
      'imageCacheEnd': _endImageCache,
      'measurementScope': {
        'inputClock': 'Dart monotonic Stopwatch; relative microseconds',
        'inputStart': 'HardwareKeyboard global handler observation; registered '
            'after binding initialization, so FocusManager may handle the key '
            'first; observedFocusAtHandler is not guaranteed pre-dispatch focus',
        'focusAssociation': 'Latest preceding down/repeat input observation; '
            'coalescing and non-causal focus changes are possible',
        'focusIdentity': 'Process-local identityHashCode of FocusNode; labels '
            'may be null because Flutter compiles debugLabel out of '
            'profile/release. Identity is not comparable across process runs.',
        'frameFeedback': 'First observed framework post-frame callback in an '
            'engine frame numbered later than the input observation; framework '
            'render submission only, not raster completion or display time',
        'frameTiming': 'Engine FrameTiming durations with frame-number window '
            'filter; report callback time is not frame execution time',
        'lateTimingDrainMs': 1500,
        'nativeInputOrDisplayLatency': false,
        'adbRoundTripUsedAsUiLatency': false,
        'probeSchedulesExtraFrames': false,
      },
      'frames': _frames,
      'inputs': _inputs,
      'focusEvents': _focusEvents,
    };
  }

  Map<String, Object?> _durationSummary(String field, double budget) {
    final values = _frames.map((frame) => frame[field]! as int).toList()
      ..sort();
    if (values.isEmpty) {
      return {'p50Us': null, 'p95Us': null, 'maxUs': null, 'overBudget': 0};
    }
    int percentile(double fraction) =>
        values[(values.length * fraction).ceil() - 1];
    return {
      'p50Us': percentile(0.5),
      'p95Us': percentile(0.95),
      'maxUs': values.last,
      'overBudget': values.where((value) => value > budget).length,
    };
  }
}

/// F9 starts one window. F10 toggles start/finish for TVs that do not deliver
/// F9 to Flutter; it is ignored during the late-timing drain. No automatic
/// repeated sampling.
/// Window-end logging is ASCII-safe JSON so logcat line boundaries survive
/// labels containing Chinese text. Reassemble the `payload` strings by part.
class TvPerformanceProbe {
  TvPerformanceProbe._({
    required this.enabled,
    required this.television,
    required this.onLog,
    required this.nowMicros,
    this.drainDuration = const Duration(milliseconds: 1500),
  });

  @visibleForTesting
  factory TvPerformanceProbe.testing({
    required bool enabled,
    required bool television,
    required void Function(String) onLog,
    required int Function() nowMicros,
    Duration drainDuration = const Duration(milliseconds: 1500),
  }) =>
      TvPerformanceProbe._(
        enabled: enabled,
        television: television,
        onLog: onLog,
        nowMicros: nowMicros,
        drainDuration: drainDuration,
      );

  final bool enabled;
  final bool television;
  final void Function(String) onLog;
  final int Function() nowMicros;
  final Duration drainDuration;
  static TvPerformanceProbe? _instance;
  static int _nextRun = 0;
  static bool _initializationMarkerReported = false;
  bool _installed = false;
  bool _installMarkerReported = false;
  int _controlMarkersReported = 0;
  int _idleKeyMarkersReported = 0;
  int? _registeredKeyboardIdentity;
  TvPerformanceCollector? _collector;
  Timer? _deadline;
  Timer? _drain;
  bool _postFrameScheduled = false;

  static void initialize() {
    if (!kazumiTvPerformanceEnabled) return;
    if (!_initializationMarkerReported) {
      _initializationMarkerReported = true;
      debugPrintSynchronously(
          jsonEncode({
            'tag': 'KAZUMI_TV_PERF_CONTROL',
            'event': 'initialize',
            'enabled': true,
            'television': TvMode.enabled,
            'mode':
                kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
            'hardwareKeyboardIdentity':
                identityHashCode(HardwareKeyboard.instance),
            'keyDataHandlerReady':
                WidgetsBinding.instance.platformDispatcher.onKeyData != null,
          }),
          wrapWidth: null);
    }
    if (!TvMode.enabled || _instance != null) {
      return;
    }
    final clock = Stopwatch()..start();
    _instance = TvPerformanceProbe._(
      enabled: true,
      television: true,
      // Output follows stop + timing drain; throttling avoids Android dropping
      // the tail of a burst. Collection and timing never use this print queue.
      onLog: (line) => debugPrintThrottled(line, wrapWidth: null),
      nowMicros: () => clock.elapsedMicroseconds,
    )..install();
  }

  @visibleForTesting
  bool get installed => _installed;

  @visibleForTesting
  bool get sampling => _collector?.isOpen ?? false;

  void install() {
    if (_installed || !enabled || !television) return;
    _installed = true;
    SchedulerBinding.instance.addTimingsCallback(_timings);
    _registeredKeyboardIdentity = identityHashCode(HardwareKeyboard.instance);
    HardwareKeyboard.instance.addHandler(_key);
    FocusManager.instance.addListener(_focus);
    if (!_installMarkerReported) {
      _installMarkerReported = true;
      onLog(jsonEncode({
        'tag': 'KAZUMI_TV_PERF_CONTROL',
        'event': 'install',
        'enabled': enabled,
        'television': television,
        'hardwareKeyboardIdentity': _registeredKeyboardIdentity,
        'keyDataHandlerReady':
            WidgetsBinding.instance.platformDispatcher.onKeyData != null,
      }));
    }
  }

  void dispose() {
    if (!_installed) return;
    _installed = false;
    _deadline?.cancel();
    _drain?.cancel();
    _collector = null;
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    HardwareKeyboard.instance.removeHandler(_key);
    FocusManager.instance.removeListener(_focus);
  }

  bool _key(KeyEvent event) {
    final logical = event.logicalKey;
    // A bounded pre-window sample can reveal a TV's unexpected logical-key
    // mapping. Never log ordinary input while collecting or draining a window.
    if (_collector == null &&
        event is KeyDownEvent &&
        !event.synthesized &&
        _idleKeyMarkersReported < 4) {
      _idleKeyMarkersReported++;
      onLog(jsonEncode({
        'tag': 'KAZUMI_TV_PERF_CONTROL',
        'event': 'idle_key',
        'seq': _idleKeyMarkersReported,
        'logicalKeyId': logical.keyId,
        'keyLabel': logical.keyLabel,
        'debugName': logical.debugName,
        'physicalKeyId': event.physicalKey.usbHidUsage,
        'synthesized': false,
        'sampling': false,
      }));
    }
    if (logical == LogicalKeyboardKey.f9 || logical == LogicalKeyboardKey.f10) {
      if (_controlMarkersReported < 4) {
        _controlMarkersReported++;
        onLog(jsonEncode({
          'tag': 'KAZUMI_TV_PERF_CONTROL',
          'event': 'control_key',
          'seq': _controlMarkersReported,
          'control': logical == LogicalKeyboardKey.f9 ? 'F9' : 'F10',
          'type': event is KeyDownEvent
              ? 'down'
              : (event is KeyRepeatEvent ? 'repeat' : 'up'),
          'logicalKeyId': logical.keyId,
          'physicalKeyId': event.physicalKey.usbHidUsage,
          'synthesized': event.synthesized,
          'samplingBefore': sampling,
          'hardwareKeyboardIdentity':
              identityHashCode(HardwareKeyboard.instance),
          'registeredKeyboardIdentity': _registeredKeyboardIdentity,
          'keyDataHandlerReady':
              WidgetsBinding.instance.platformDispatcher.onKeyData != null,
        }));
      }
      if (event is KeyDownEvent && !event.synthesized) {
        if (logical == LogicalKeyboardKey.f9) {
          _start();
        } else if (_collector == null) {
          _start();
        } else if (_collector!.isOpen) {
          _stop('f10');
        }
      }
      return true;
    }
    final collector = _collector;
    if (collector == null || !collector.isOpen) return false;
    if (collector.expired) {
      _stop('timeout');
      return false;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final reason = collector.addInput(
      key: logical.debugName ?? 'keyId:${logical.keyId}',
      type: event is KeyRepeatEvent ? 'repeat' : 'down',
      receivedFrameNumber: _frameNumber,
      observedFocus: _focusLabel,
      observedFocusIdentity: _focusIdentity,
      synthesized: event.synthesized,
    );
    if (reason != null) {
      _stop(reason);
    } else if (collector.hasPendingFrameInputs) {
      _schedulePostFrame();
    }
    return false;
  }

  int get _frameNumber =>
      WidgetsBinding.instance.platformDispatcher.frameData.frameNumber;
  String? get _focusLabel => FocusManager.instance.primaryFocus?.debugLabel;
  int? get _focusIdentity {
    final focus = FocusManager.instance.primaryFocus;
    return focus == null ? null : identityHashCode(focus);
  }

  void _start() {
    // Do not restart an active window or discard a window awaiting late frames.
    if (_collector != null) return;
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final reportedRate = views.isEmpty ? 0.0 : views.first.display.refreshRate;
    final validRate = reportedRate.isFinite && reportedRate > 0;
    _collector = TvPerformanceCollector(
      runId: '${DateTime.now().toUtc().microsecondsSinceEpoch}-${++_nextRun}',
      nowMicros: nowMicros,
      mode: kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
      refreshRateHz: validRate ? reportedRate : 60.0,
      refreshRateSource: validRate ? 'FlutterView.display' : 'fallback_60Hz',
      startFrameNumber: _frameNumber,
      startFocus: _focusLabel,
      startFocusIdentity: _focusIdentity,
      startImageCache: _imageCache(),
    );
    _deadline = Timer(const Duration(seconds: 60), () => _stop('timeout'));
  }

  void _timings(List<FrameTiming> timings) {
    final collector = _collector;
    if (collector == null) return;
    if (collector.isOpen && collector.expired) _stop('timeout');
    final reason = collector.addFrames(timings);
    if (reason != null) _stop(reason);
  }

  void _focus() {
    final collector = _collector;
    if (collector == null || !collector.isOpen) return;
    if (collector.expired) {
      _stop('timeout');
      return;
    }
    collector.focusChanged(_focusLabel, identity: _focusIdentity);
  }

  void _schedulePostFrame() {
    if (_postFrameScheduled) return;
    _postFrameScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _postFrameScheduled = false;
      // An idle window can close without producing a frame. Reuse its single
      // pending callback for the current window, rather than leaving the new
      // window behind a stale callback or accumulating callbacks per window.
      final collector = _collector;
      if (!_installed || collector == null || !collector.isOpen) {
        return;
      }
      if (collector.expired) {
        _stop('timeout');
        return;
      }
      collector.submittedFrame(_frameNumber);
      if (collector.hasPendingFrameInputs) _schedulePostFrame();
    }, debugLabel: 'KazumiTV optional input-frame probe');
    // Do not request a frame: idle/no-op keys must remain idle/no-op.
  }

  void _stop(String reason) {
    final collector = _collector;
    if (collector == null || !collector.isOpen) return;
    _deadline?.cancel();
    collector.stop(
      reason: reason,
      endFrameNumber: _frameNumber,
      endFocus: _focusLabel,
      endFocusIdentity: _focusIdentity,
      endImageCache: _imageCache(),
    );
    _drain = Timer(drainDuration, () {
      if (!_installed || !identical(_collector, collector)) return;
      final report = collector.report();
      // Use the actual adapter wait when tests shorten it.
      (report['measurementScope']!
              as Map<String, Object?>)['lateTimingDrainMs'] =
          drainDuration.inMilliseconds;
      for (final line in encodeLogChunks(report)) {
        onLog(line);
      }
      _collector = null;
    });
  }

  Map<String, int> _imageCache() {
    final cache = PaintingBinding.instance.imageCache;
    return {
      'currentSize': cache.currentSize,
      'currentSizeBytes': cache.currentSizeBytes,
      'liveImageCount': cache.liveImageCount,
      'pendingImageCount': cache.pendingImageCount,
      'maximumSizeBytes': cache.maximumSizeBytes,
    };
  }

  /// Each line is a standalone JSON envelope. Payload is a slice of the full
  /// report JSON, not a separately parseable report; concatenate parts first.
  @visibleForTesting
  static List<String> encodeLogChunks(Map<String, Object?> report) {
    final raw = jsonEncode(report);
    // ASCII escapes also avoid splitting UTF-16 surrogate pairs in a chunk.
    final ascii = StringBuffer();
    for (final unit in raw.codeUnits) {
      if (unit > 0x7f) {
        ascii.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
      } else {
        ascii.writeCharCode(unit);
      }
    }
    final payload = ascii.toString();
    // This TV's Dart/logcat transport truncates a print at 1023 ASCII bytes.
    // Worst-case envelope escaping doubles each payload character; 350 leaves
    // space for runId and counters under a conservative 900-byte line cap.
    const size = 350;
    final total = (payload.length / size).ceil();
    return List.generate(total, (index) {
      final end = (index + 1) * size;
      final line = jsonEncode({
        'tag': 'KAZUMI_TV_PERF',
        'runId': report['runId'],
        'part': index + 1,
        'total': total,
        'payload': payload.substring(
            index * size, end < payload.length ? end : payload.length),
      });
      if (line.length > 900) {
        throw StateError('Performance report chunk exceeds logcat bound.');
      }
      return line;
    });
  }
}
