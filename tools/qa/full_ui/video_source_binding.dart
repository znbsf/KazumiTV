// Explicit parserQa full-UI entrypoint only. Never imported by lib/.
import 'dart:async';
import 'dart:convert';

import 'package:kazumi/services/platform/webview_feature_service.dart';
import 'package:kazumi/services/video_source/services.dart';
import 'package:kazumi/utils/async_session.dart';

import '../source_batch/app_fallback_service.dart';
import '../source_batch/gecko_controller.dart';

/// One full-UI process owns this gate; routes share retirement, not parsers.
/// A failed retirement quarantines subsequent routes as well as this one.
class QaUiRetirementGate {
  Future<void> _tail = Future<void>.value();
  bool _tainted = false;
}

class QaUiVideoSourceBinding implements IVideoSourceService {
  QaUiVideoSourceBinding({
    required this.gate,
    required this.enabled,
    required this.capabilityEligible,
    required this.primaryFactory,
    required this.fallbackFactory,
    this.primaryBudget = const Duration(seconds: 10),
    this.totalBudget = const Duration(seconds: 25),
    this.cleanupBudget = const Duration(seconds: 2),
  });

  factory QaUiVideoSourceBinding.production({
    required QaUiRetirementGate gate,
  }) {
    late final QaUiVideoSourceBinding binding;
    binding = QaUiVideoSourceBinding(
      gate: gate,
      enabled: true,
      capabilityEligible: () =>
          WebViewFeatureService.needsLegacyPlayerCompat &&
          !WebViewFeatureService.isDocumentStartScriptSupported,
      primaryFactory: () =>
          WebViewVideoSourceService(diagnosticSink: binding._diagnostic),
      fallbackFactory: (headers) => WebViewVideoSourceService(
        nestedPageTimeout: Duration.zero,
        controllerFactory: () => GeckoQaController(headers['user-agent']!),
        diagnosticSink: binding._diagnostic,
      ),
    );
    return binding;
  }

  final QaUiRetirementGate gate;
  final bool enabled;
  final bool Function() capabilityEligible;
  final IVideoSourceService Function() primaryFactory;
  final IVideoSourceService Function(Map<String, String>) fallbackFactory;
  final Duration primaryBudget, totalBudget, cleanupBudget;
  final _sessions = AsyncSessionOwner();
  final _logs = StreamController<String>.broadcast();
  Stream<String> get onLog => _logs.stream;
  Future<void> _lastTask = Future<void>.value();
  Future<void>? _disposal;
  _Admission? _current;
  IVideoSourceService? _active;
  bool _disposed = false;

  void _diagnostic(String record) {
    if (!_logs.isClosed) _logs.add(record);
  }

  @override
  Future<VideoSource> resolve(String url,
          {required bool useLegacyParser,
          int offset = 0,
          Duration timeout = const Duration(seconds: 15)}) =>
      _enqueue(url, useLegacyParser, offset, timeout, null);

  Future<VideoSource> resolveWithHeaders(String url,
          {required bool useLegacyParser,
          required int offset,
          required Duration timeout,
          required Map<String, String> headers}) =>
      _enqueue(url, useLegacyParser, offset, timeout,
          Map<String, String>.unmodifiable(headers));

  Future<VideoSource> _enqueue(String url, bool legacy, int offset,
      Duration timeout, Map<String, String>? headers) {
    if (_disposed) return Future.error(const VideoSourceCancelledException());
    _current?.cancel();
    _active?.cancel();
    final ua = headers?['user-agent'];
    final experimental = enabled &&
        !legacy &&
        headers != null &&
        ua != null &&
        ua.isNotEmpty &&
        capabilityEligible();
    final request = _Admission(_sessions.begin(), experimental, headers);
    _current = request;
    final task = gate._tail.then((_) async {
      try {
        return await _run(request, url, legacy, offset, timeout);
      } finally {
        if (identical(_current, request)) _current = null;
      }
    });
    // Keep retirement in the shared tail even if the caller cancels early.
    gate._tail = task.then<void>((_) {}, onError: (_) {});
    _lastTask = gate._tail;
    return Future.any<VideoSource>([
      task,
      request.cancelled.future.then<VideoSource>(
          (_) => throw const VideoSourceCancelledException()),
    ]);
  }

  Duration _remaining(_Admission request) {
    request.check(_disposed);
    final remaining = totalBudget - request.clock.elapsed;
    if (remaining <= Duration.zero) {
      throw VideoSourceTimeoutException(totalBudget);
    }
    return remaining;
  }

  Future<VideoSource> _run(_Admission request, String url, bool legacy,
      int offset, Duration timeout) async {
    request.check(_disposed);
    if (gate._tainted) {
      throw StateError('QA UI previous retirement unconfirmed');
    }
    final IVideoSourceService service;
    if (request.experimental) {
      // Admission/queue time consumes the SAME 25s, never a renewed budget.
      final remaining = _remaining(request);
      final headers = request.headers!;
      service = QaAppFallbackService(
        primaryFactory:
            primaryFactory, // fresh instance for every phase/request
        fallbackFactory: () => fallbackFactory(headers),
        enabled: true,
        eligible: true, // frozen from the existing capability and mode gate
        primaryBudget: primaryBudget,
        totalBudget: remaining,
        cleanupBudget: cleanupBudget,
        onEvent: (event) => _diagnostic(jsonEncode({
          ...event,
          'admission_elapsed_ms': request.clock.elapsedMilliseconds,
        })),
      );
    } else {
      // Not a QA 10s attempt: preserve ordinary service/native HTML budgets.
      service = primaryFactory();
    }
    _active = service;
    late final VideoSource source;
    try {
      source = await Future.any<VideoSource>([
        service.resolve(url,
            useLegacyParser: legacy, offset: offset, timeout: timeout),
        request.cancelled.future.then<VideoSource>(
            (_) => throw const VideoSourceCancelledException()),
      ]);
      request.check(_disposed);
    } finally {
      service.cancel();
      try {
        await service.dispose().timeout(cleanupBudget);
      } catch (_) {
        gate._tainted = true;
        _diagnostic('{"stage":"cleanup_unconfirmed"}');
        rethrow;
      } finally {
        if (identical(_active, service)) _active = null;
      }
    }
    // Cleanup/cancellation may invalidate even a successfully parsed candidate.
    request.check(_disposed);
    if (request.experimental) _remaining(request);
    return source;
  }

  @override
  void cancel() {
    _sessions.cancel();
    _current?.cancel();
    _active?.cancel();
  }

  @override
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _sessions.close();
    cancel();
    // Do not wait for a newer route's task in the shared gate (would deadlock).
    await _lastTask;
    unawaited(_logs.close());
    if (gate._tainted) throw StateError('QA UI retirement unconfirmed');
  }
}

class _Admission {
  _Admission(this.session, this.experimental, this.headers);
  final AsyncSession session;
  final bool experimental;
  final Map<String, String>? headers;
  final clock = Stopwatch()..start();
  final cancelled = Completer<void>();
  void cancel() {
    if (!cancelled.isCompleted) cancelled.complete();
  }

  void check(bool disposed) {
    if (disposed || session.isStale || cancelled.isCompleted) {
      throw const VideoSourceCancelledException();
    }
  }
}
