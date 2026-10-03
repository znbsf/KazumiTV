import 'dart:async';

import 'package:kazumi/webview/video/video_webview_controller.dart';
import 'package:kazumi/services/video_source/video_source_service.dart';

/// WebView 视频源解析服务
///
/// 使用 WebView 解析视频页面，提取视频源 URL。
/// WebView 实例在服务生命周期内复用，切换集数时调用 unloadPage 释放页面资源，
/// 仅在 [dispose] 时才真正销毁 WebView。
class WebViewVideoSourceService implements IVideoSourceService {
  WebViewVideoSourceService({
    VideoWebviewController Function()? controllerFactory,
  }) : _controllerFactory =
            controllerFactory ?? VideoWebviewControllerFactory.getController;

  final VideoWebviewController Function() _controllerFactory;
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
    request.throwIfNotCurrent(_activeRequest);

    var didStartLoad = false;
    Future<void>? loadFuture;
    StreamSubscription<VideoParserEvent>? parserSubscription;
    Timer? parserTimer;
    final parserResult = Completer<VideoParserEvent>();
    try {
      if (_webview == null) {
        final webview = _controllerFactory();
        try {
          await webview.init();
        } catch (_) {
          await webview.dispose();
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
      loadFuture = Future<void>.sync(
        () => _webview!.loadUrl(
          episodeUrl,
          useLegacyParser,
          offset: offset,
        ),
      );

      // 同时监听两个 Future 的错误，避免加载尚未返回时解析流错误
      // 成为未处理异常。保持原有“loadUrl 完成后开始解析超时”的语义。
      final loadedAndParsed = Future.wait<Object?>([
        loadFuture.then<void>((_) {
          request.throwIfNotCurrent(_activeRequest);
          if (!parserResult.isCompleted) {
            parserTimer = Timer(timeout, () {
              if (!parserResult.isCompleted) {
                parserResult
                    .completeError(VideoSourceTimeoutException(timeout));
              }
            });
          }
        }),
        parserResult.future,
      ], eagerError: true)
          .then((results) => results[1] as VideoParserEvent);
      final cancelFuture = request.cancelled.then<VideoParserEvent>((_) {
        throw const VideoSourceCancelledException();
      });
      final event = await Future.any([loadedAndParsed, cancelFuture]);

      request.throwIfNotCurrent(_activeRequest);

      return VideoSource(
        url: event.url,
        offset: event.offset,
        type: VideoSourceType.online,
        format: event.format,
      );
    } catch (e) {
      if (e is VideoSourceCancelledException) {
        rethrow;
      }
      request.throwIfNotCurrent(_activeRequest);
      rethrow;
    } finally {
      parserTimer?.cancel();
      await parserSubscription?.cancel();
      if (parserSubscription != null && !parserResult.isCompleted) {
        parserResult.completeError(const VideoSourceCancelledException());
      }
      if (didStartLoad) {
        // 取消时也要等旧加载命令收尾再卸页，下一请求才可使用同一
        // WebView；卸页期间的迟到事件已不再有本轮订阅。
        try {
          await loadFuture;
        } catch (_) {
          // 加载异常已由上面的等待路径处理；这里只等待命令收尾。
        }
        await _webview?.unloadPage();
      }
      if (identical(_activeRequest, request)) {
        _activeRequest = null;
      }
    }
  }

  @override
  void cancel() {
    _activeRequest?.cancel();
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
