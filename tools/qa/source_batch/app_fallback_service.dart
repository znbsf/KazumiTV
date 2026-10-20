// QA only. Product entrypoints must not import this experimental policy.
import 'dart:async';

import 'package:kazumi/services/video_source/video_source_service.dart';

class QaAppFallbackService implements IVideoSourceService {
  QaAppFallbackService({
    required this.primaryFactory,
    required this.fallbackFactory,
    required this.enabled,
    required this.eligible,
    this.totalBudget = const Duration(seconds: 25),
    this.primaryBudget = const Duration(seconds: 15),
    this.cleanupBudget = const Duration(seconds: 2),
    this.onEvent,
  });

  final IVideoSourceService Function() primaryFactory, fallbackFactory;
  final bool enabled, eligible;
  final Duration totalBudget, primaryBudget, cleanupBudget;
  final void Function(Map<String, Object?> event)? onEvent;
  Future<void> _tail = Future<void>.value();
  _Request? _current;
  IVideoSourceService? _service;
  bool _disposed = false, _tainted = false;
  int _generation = 0;

  void _event(_Request request, String phase, String stage, [Object? error]) {
    try {
      onEvent?.call({
        'generation': request.generation,
        'phase': phase,
        'stage': stage,
        'elapsed_ms': request.clock.elapsedMilliseconds,
        'epoch_ms': DateTime.now().millisecondsSinceEpoch,
        if (error != null) 'error_type': error.runtimeType.toString(),
      });
    } catch (_) {/* Diagnostics never change the request outcome. */}
  }

  Duration _remaining(_Request request) {
    request.check(_current, _disposed);
    final remaining = totalBudget - request.clock.elapsed;
    if (remaining <= Duration.zero) {
      throw VideoSourceTimeoutException(totalBudget);
    }
    return remaining;
  }

  @override
  Future<VideoSource> resolve(String episodeUrl,
      {required bool useLegacyParser,
      int offset = 0,
      Duration timeout = const Duration(seconds: 15)}) {
    if (_disposed) return Future.error(const VideoSourceCancelledException());
    _current?.cancel();
    _service?.cancel();
    final request = _Request(++_generation);
    _current = request;
    final future = _tail.then((_) async {
      _remaining(request);
      if (_tainted) throw StateError('QA previous engine cleanup unconfirmed');
      try {
        try {
          return await _phase(
              request,
              primaryFactory,
              'primary',
              episodeUrl,
              useLegacyParser,
              offset,
              timeout < primaryBudget ? timeout : primaryBudget);
        } catch (error) {
          request.check(_current, _disposed);
          if (!enabled ||
              !eligible ||
              useLegacyParser ||
              (error is! VideoSourceTimeoutException &&
                  error is! VideoSourceNotFoundException)) {
            rethrow;
          }
          // A single fallback consumes the same request's remaining budget.
          final remaining = _remaining(request);
          _event(request, 'fallback', 'selected', error);
          return await _phase(request, fallbackFactory, 'fallback', episodeUrl,
              useLegacyParser, offset, remaining);
        }
      } finally {
        if (identical(_current, request)) _current = null;
      }
    });
    _tail = future.then<void>((_) {}, onError: (_) {});
    return future;
  }

  Future<VideoSource> _phase(
      _Request request,
      IVideoSourceService Function() factory,
      String phase,
      String url,
      bool legacy,
      int offset,
      Duration timeout) async {
    final remaining = _remaining(request);
    final phaseBudget = timeout < remaining ? timeout : remaining;
    final service = factory();
    _service = service;
    _event(request, phase, 'started');
    late final VideoSource source;
    try {
      source = await Future.any<VideoSource>([
        service.resolve(url,
            useLegacyParser: legacy, offset: offset, timeout: phaseBudget),
        request.cancelled.future.then<VideoSource>(
            (_) => throw const VideoSourceCancelledException()),
      ]).timeout(phaseBudget,
          onTimeout: () => throw VideoSourceTimeoutException(phaseBudget));
      _remaining(request);
      _event(request, phase, 'resolved');
    } catch (error) {
      _event(request, phase, 'failed', error);
      rethrow;
    } finally {
      service.cancel();
      _event(request, phase, 'retiring');
      try {
        await service.dispose().timeout(cleanupBudget);
        _event(request, phase, 'retired');
      } catch (error) {
        _tainted = true;
        _event(request, phase, 'cleanup_unconfirmed', error);
        rethrow;
      } finally {
        if (identical(_service, service)) _service = null;
      }
    }
    // A candidate is not committed until asynchronous retirement finishes.
    // Cancellation, supersession and deadline expiry can all happen there.
    _remaining(request);
    _event(request, phase, 'accepted');
    return source;
  }

  @override
  void cancel() {
    _current?.cancel();
    _service?.cancel();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    cancel();
    await _tail;
    if (_tainted) throw StateError('QA engine cleanup unconfirmed');
  }
}

class _Request {
  _Request(this.generation);
  final int generation;
  final Stopwatch clock = Stopwatch()..start();
  final Completer<void> cancelled = Completer<void>();
  void cancel() {
    if (!cancelled.isCompleted) cancelled.complete();
  }

  void check(_Request? current, bool disposed) {
    if (disposed || cancelled.isCompleted || !identical(current, this)) {
      throw const VideoSourceCancelledException();
    }
  }
}
