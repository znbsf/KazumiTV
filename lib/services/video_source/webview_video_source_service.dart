import 'dart:async';
import 'package:kazumi/services/logging/playback_trace.dart';

import 'package:kazumi/webview/video/video_webview_controller.dart';
import 'package:kazumi/webview/video/video_parser_url.dart';
import 'package:kazumi/services/video_source/video_source_service.dart';

/// WebView 视频源解析服务
///
/// 使用 WebView 解析视频页面，提取视频源 URL。
/// WebView 实例在服务生命周期内复用，切换集数时调用 unloadPage 释放页面资源，
/// 仅在 [dispose] 时才真正销毁 WebView。
class WebViewVideoSourceService implements IVideoSourceService {
  WebViewVideoSourceService({
    VideoWebviewController Function()? controllerFactory,
    Duration cleanupTimeout = const Duration(seconds: 2),
    Duration nestedPageTimeout = const Duration(seconds: 10),
    PlaybackTraceSink? diagnosticSink,
  })  : _nestedPageTimeout = nestedPageTimeout,
        _cleanupTimeout = cleanupTimeout,
        _diagnosticSink = diagnosticSink,
        _controllerFactory =
            controllerFactory ?? VideoWebviewControllerFactory.getController;

  final VideoWebviewController Function() _controllerFactory;
  final Duration _cleanupTimeout;
  final Duration _nestedPageTimeout;
  final PlaybackTraceSink? _diagnosticSink;
  VideoWebviewController? _webview;
  StreamSubscription? _logSubscription;

  // 单个服务实例持有一个 WebView，因此解析任务按实例串行执行。
  // 下载并行通过多个服务实例实现。
  Future<void>? _resolveTail = Future<void>.value();
  _ResolveRequest? _activeRequest;

  final StreamController<String> _logController =
      StreamController<String>.broadcast();
  Stream<String> get onLog => _logController.stream;

  @override
  Future<VideoSource> resolve(
    String episodeUrl, {
    required bool useLegacyParser,
    int offset = 0,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final resolveTail = _resolveTail;
    if (resolveTail == null) {
      throw const VideoSourceCancelledException();
    }

    _activeRequest?.cancel();
    final request = _ResolveRequest();
    _activeRequest = request;

    final resolveFuture = resolveTail.then(
      (_) => _runResolve(
        request,
        episodeUrl,
        useLegacyParser: useLegacyParser,
        offset: offset,
        timeout: timeout,
      ),
    );

    _resolveTail = resolveFuture.then<void>((_) {}, onError: (_) {});
    return resolveFuture;
  }

  Future<VideoSource> _runResolve(
    _ResolveRequest request,
    String episodeUrl, {
    required bool useLegacyParser,
    required int offset,
    required Duration timeout,
  }) async {
    final clock = Stopwatch()..start();
    final candidates = <String>{};
    final originalPage = Uri.tryParse(episodeUrl)?.removeFragment();
    try {
      try {
        return await _resolvePage(request, episodeUrl,
            useLegacyParser: useLegacyParser,
            offset: offset,
            timeout: timeout, onCandidate: (url) {
          final candidate = nestedVideoPageUrl(url);
          if (candidate != null &&
              Uri.parse(candidate).removeFragment() != originalPage &&
              candidates.length < 2) {
            candidates.add(candidate);
          }
        });
      } catch (error) {
        request.throwIfNotCurrent(_activeRequest);
        if (error is! VideoSourceTimeoutException &&
            error is! VideoSourceNotFoundException) {
          rethrow;
        }
        final remaining = timeout + _nestedPageTimeout - clock.elapsed;
        if (candidates.length != 1 ||
            remaining <= Duration.zero ||
            _nestedPageTimeout <= Duration.zero) {
          rethrow;
        }
        final budget =
            remaining < _nestedPageTimeout ? remaining : _nestedPageTimeout;
        final page = candidates.single;
        final trace = PlaybackTrace('nested_page', sink: _diagnosticSink);
        trace.event('fallback',
            url: page,
            detail:
                'reason=${error.runtimeType} hop=1 timeoutMs=${budget.inMilliseconds}');
        try {
          // Deliberately do not collect candidates from this page: never recurse.
          final source = await _resolvePage(request, page,
              useLegacyParser: useLegacyParser,
              offset: offset,
              timeout: budget);
          trace.finish('resolved');
          return source;
        } catch (error) {
          trace.finish(
              error is VideoSourceCancelledException ? 'cancelled' : 'failed',
              error: error);
          rethrow;
        }
      }
    } finally {
      if (identical(_activeRequest, request)) _activeRequest = null;
    }
  }

  Future<VideoSource> _resolvePage(
    _ResolveRequest request,
    String episodeUrl, {
    required bool useLegacyParser,
    required int offset,
    required Duration timeout,
    void Function(String)? onCandidate,
  }) async {
    request.throwIfNotCurrent(_activeRequest);

    final trace = PlaybackTrace('parser', sink: _diagnosticSink);
    trace.event('initialize',
        url: episodeUrl,
        detail: 'legacy=$useLegacyParser timeoutMs=${timeout.inMilliseconds}');
    StreamSubscription<VideoParserDiagnostic>? diagnosticSubscription;
    StreamSubscription<String>? candidateSubscription;
    final pageClock = Stopwatch()..start();
    var didStartLoad = false;
    Future<void>? loadFuture;
    StreamSubscription<VideoParserEvent>? parserSubscription;
    final parserResult = Completer<VideoParserEvent>();
    try {
      if (_webview == null) {
        final webview = _controllerFactory();
        try {
          await Future.any<void>([
            webview.init(),
            request.cancelled
                .then<void>((_) => throw const VideoSourceCancelledException()),
          ]).timeout(timeout,
              onTimeout: () => throw VideoSourceTimeoutException(timeout));
        } catch (_) {
          try {
            await webview.dispose().timeout(_cleanupTimeout);
          } catch (_) {
            // A failed or unfinished controller is never reused.
          }
          rethrow;
        }
        _webview = webview;

        _logSubscription = webview.onLog.listen((log) {
          if (!_logController.isClosed) {
            _logController.add(log);
          }
        });
      }

      request.throwIfNotCurrent(_activeRequest);

      diagnosticSubscription = _webview!.onDiagnostic.listen((event) {
        if (request.isCurrent(_activeRequest)) {
          trace.event(event.stage, url: event.url, detail: event.detail);
        }
      });
      if (onCandidate != null) {
        candidateSubscription = _webview!.onNestedPageCandidate.listen((url) {
          if (request.isCurrent(_activeRequest)) onCandidate(url);
        });
      }

      // 广播流不会重放事件：iframe/原生拦截可能在 loadUrl 返回前
      // 已经给出 URL，因此必须先订阅，且订阅只属于当前解析请求。
      parserSubscription = _webview!.onVideoURLParser.listen(
        (event) {
          if (request.isCurrent(_activeRequest) && !parserResult.isCompleted) {
            parserResult.complete(event);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (request.isCurrent(_activeRequest) && !parserResult.isCompleted) {
            parserResult.completeError(error, stackTrace);
          }
        },
        onDone: () {
          if (request.isCurrent(_activeRequest) && !parserResult.isCompleted) {
            parserResult.completeError(const VideoSourceNotFoundException());
          }
        },
      );

      didStartLoad = true;
      trace.event('load', url: episodeUrl);
      loadFuture = Future<void>.sync(
        () => _webview!.loadUrl(
          episodeUrl,
          useLegacyParser,
          offset: offset,
        ),
      );

      // 同时监听两个 Future 的错误，避免加载尚未返回时解析流错误
      // 成为未处理异常。期限覆盖加载与解析，防止加载不返回绕过超时。
      final loadedAndParsed = Future.wait<Object?>([
        loadFuture,
        parserResult.future,
      ], eagerError: true)
          .then((results) => results[1] as VideoParserEvent)
          .timeout(timeout - pageClock.elapsed,
              onTimeout: () => throw VideoSourceTimeoutException(timeout));
      final cancelFuture = request.cancelled.then<VideoParserEvent>((_) {
        throw const VideoSourceCancelledException();
      });
      final event = await Future.any([loadedAndParsed, cancelFuture]);

      request.throwIfNotCurrent(_activeRequest);

      trace.event('resolved', url: event.url, detail: event.format.name);
      trace.finish('resolved');

      return VideoSource(
        url: event.url,
        offset: event.offset,
        type: VideoSourceType.online,
        format: event.format,
      );
    } catch (e) {
      if (e is VideoSourceCancelledException) {
        trace.finish('cancelled');
        rethrow;
      }
      if (!request.isCurrent(_activeRequest)) {
        trace.finish('superseded');
      } else {
        trace.finish(e is VideoSourceTimeoutException ? 'timeout' : 'failed',
            error: e);
      }
      request.throwIfNotCurrent(_activeRequest);
      rethrow;
    } finally {
      await diagnosticSubscription?.cancel();
      await candidateSubscription?.cancel();
      await parserSubscription?.cancel();
      if (parserSubscription != null && !parserResult.isCompleted) {
        parserResult.completeError(const VideoSourceCancelledException());
      }
      if (didStartLoad) {
        // 取消时也要等旧加载命令收尾再卸页，下一请求才可使用同一
        // WebView；卸页期间的迟到事件已不再有本轮订阅。
        try {
          await loadFuture?.timeout(_cleanupTimeout);
        } on TimeoutException {
          await _retireWebview();
        } catch (_) {
          // 加载异常已由上面的等待路径处理；这里只等待命令收尾。
        }
        try {
          await _webview?.unloadPage().timeout(_cleanupTimeout);
        } catch (_) {
          await _retireWebview();
        }
      }
    }
  }

  @override
  void cancel() {
    _activeRequest?.cancel();
  }

  // A controller with unfinished native work must never be reused. Detach it
  // before disposal so late events cannot enter the next request's streams.
  Future<void> _retireWebview() async {
    final webview = _webview;
    _webview = null;
    await _logSubscription?.cancel();
    _logSubscription = null;
    try {
      await webview?.dispose().timeout(_cleanupTimeout);
    } catch (_) {
      // Native cleanup is best effort; the retired instance remains isolated.
    }
  }

  @override
  Future<void> dispose() async {
    final resolveTail = _resolveTail;
    _resolveTail = null;
    cancel();
    await resolveTail;
    _activeRequest = null;
    await _logSubscription?.cancel();
    _logSubscription = null;
    if (!_logController.isClosed) {
      await _logController.close();
    }
    await _webview?.dispose();
    _webview = null;
  }
}

class _ResolveRequest {
  final Completer<void> _cancelled = Completer<void>();

  Future<void> get cancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }

  void throwIfNotCurrent(_ResolveRequest? current) {
    if (!isCurrent(current)) {
      throw const VideoSourceCancelledException();
    }
  }

  bool isCurrent(_ResolveRequest? current) =>
      !_cancelled.isCompleted && identical(current, this);
}
