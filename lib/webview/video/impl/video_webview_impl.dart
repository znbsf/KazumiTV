import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:kazumi/webview/video/video_webview_controller.dart';
import 'package:kazumi/webview/video/legacy_parser_scripts.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/network/proxy_utils.dart';
import 'package:flutter_inappwebview_android/flutter_inappwebview_android.dart'
    as android_webview;
import 'package:kazumi/webview/video/video_parser_url.dart';
import 'package:kazumi/utils/http_headers.dart';
import 'package:kazumi/services/video_source/legacy_player_compat.dart';

class VideoWebviewImpl
    extends VideoWebviewController<PlatformInAppWebViewController> {
  VideoWebviewImpl({LegacyPlayerCompat? playerCompat})
      : _injectedCompat = playerCompat;
  final LegacyPlayerCompat? _injectedCompat;
  PlatformHeadlessInAppWebView? headlessWebView;
  bool hasRegisteredHandlers = false;
  bool useLegacyParser = false;
  Timer? videoParserTimer;
  int _session = 0;
  bool _pageActive = false;
  bool _polling = false;
  bool _disposed = false;
  late final _playerCompat = _injectedCompat ??
      LegacyPlayerCompat(onDiagnostic: (stage) {
        if (_pageActive && !_disposed) {
          reportDiagnostic(
              'legacy_player_compat', LegacyPlayerCompat.endpoint, stage);
        }
      });

  @override
  Future<void> init() async {
    await _setupProxy();
    if (_disposed) return;
    headlessWebView ??= PlatformHeadlessInAppWebView(
      PlatformHeadlessInAppWebViewCreationParams(
        initialSize: const Size(360, 640),
        initialSettings: InAppWebViewSettings(
          userAgent: getRandomUA(),
          mediaPlaybackRequiresUserGesture: true,
          upgradeKnownHostsToHTTPS: false,
          mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
        ),
        onWebViewCreated: (controller) {
          if (_disposed) return;
          KazumiLogger().i('[WebView] Created (legacy fallback)');
          webviewController = controller;
          initEventController.add(true);
        },
        shouldInterceptRequest: (controller, request) async {
          if (!_pageActive || isVideoSourceLoaded) return null;
          final url = request.url.toString();
          _playerCompat.observePage(url, request.headers);
          if (isVideoParserAdUrl(url)) return null;
          // An iframe's public query can expose the media URL before its
          // JavaScript player fails on an older WebView. Reuse the existing
          // legacy decoder in both modes; no page code or authentication is
          // changed, and cross-origin documents remain inaccessible.
          final embedded = embeddedVideoParserUrl(url);
          if (embedded != null) {
            _resolve(embedded, 'Native intercepted embedded video URL');
          } else if (nestedVideoPageUrl(url, fromPlayerQuery: true)
              case final page?) {
            notifyNestedPageCandidate(page);
          } else if (!useLegacyParser &&
              (_isM3U8Url(url) || _isRangeVideoRequest(url, request.headers))) {
            final page = nestedVideoPageUrl(url);
            if (page != null) {
              notifyNestedPageCandidate(page);
            } else {
              _resolve(url, 'Native intercepted video URL');
            }
          }
          return null;
        },
        onReceivedHttpError: (controller, request, response) {
          if (_pageActive) {
            reportDiagnostic('http_error', request.url.toString(),
                'status=${response.statusCode} mainFrame=${request.isForMainFrame}');
            unawaited(_tryPlayerCompat(request, response));
          }
        },
        onLoadStart: (controller, url) async {
          _log('started loading: $url');
          if (_pageActive) reportDiagnostic('load_start', '$url', '');
          if (url.toString() != 'about:blank') await _injectParser();
        },
        onLoadStop: (controller, url) async {
          _log('loading completed: $url');
          if (_pageActive) reportDiagnostic('load_stop', '$url', '');
          if (url.toString() != 'about:blank') await _injectParser();
        },
        onConsoleMessage: (controller, consoleMessage) {
          _log(
              'Console [${consoleMessage.messageLevel}]: ${consoleMessage.message}');
        },
        onReceivedError: (controller, request, error) {
          _log('Error: ${error.description} - ${request.url}');
          if (_pageActive) {
            reportDiagnostic('resource_error', request.url.toString(),
                'code=${error.type.toNativeValue()} mainFrame=${request.isForMainFrame} ${error.description}');
          }
        },
      ),
    );
    final view = headlessWebView;
    await view?.run();
    if (_disposed) await view?.dispose();
  }

  @override
  Future<void> loadUrl(String url, bool useLegacyParser,
      {int offset = 0}) async {
    await unloadPage();
    if (!hasRegisteredHandlers) {
      _addJavaScriptHandlers();
      hasRegisteredHandlers = true;
    }
    count = 0;
    this.offset = offset;
    this.useLegacyParser = useLegacyParser;
    isIframeLoaded = false;
    isVideoSourceLoaded = false;
    _pageActive = true;
    _playerCompat.begin(url, enabled: !useLegacyParser);
    videoLoadingEventController.add(true);
    _startVideoParserTimer();
    await webviewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  void _addJavaScriptHandlers() {
    webviewController?.addJavaScriptHandler(
      handlerName: 'LogBridge',
      callback: (args) {
        if (args.isNotEmpty && !args[0].toString().contains('about:blank')) {
          _log(args[0].toString());
        }
      },
    );
    // Both bridges must remain installed when the pooled WebView is reused
    // for a source with a different parser mode.
    webviewController?.addJavaScriptHandler(
      handlerName: 'JSBridgeDebug',
      callback: (args) {
        if (!_isCurrentReply(args)) return;
        final url = embeddedVideoParserUrl(args[0].toString());
        if (url != null) {
          _resolve(url, 'Iframe embedded video URL');
        } else if (nestedVideoPageUrl(args[0].toString(), fromPlayerQuery: true)
            case final page?) {
          notifyNestedPageCandidate(page);
        }
      },
    );
    webviewController?.addJavaScriptHandler(
      handlerName: 'VideoBridgeDebug',
      callback: (args) {
        if (!_isCurrentReply(args) || useLegacyParser) return;
        final url = args[0].toString();
        if (nestedVideoPageUrl(url) case final page?) {
          notifyNestedPageCandidate(page);
          return;
        }
        if (isVideoParserNetworkUrl(url) && !isVideoParserAdUrl(url)) {
          _resolve(url, 'Video source URL');
        }
      },
    );
  }

  bool _isCurrentReply(List<dynamic> args) =>
      _pageActive &&
      !isVideoSourceLoaded &&
      args.length >= 2 &&
      args[1] == _session;

  void _resolve(String url, String origin) {
    if (!_pageActive || isVideoSourceLoaded) return;
    _playerCompat.cancel();
    isIframeLoaded = true;
    isVideoSourceLoaded = true;
    videoParserTimer?.cancel();
    videoParserTimer = null;
    videoLoadingEventController.add(false);
    _log('$origin: $url');
    notifyVideoSourceResolved(url);
    // The source service owns and awaits retirement before reusing this
    // controller. Stop accepting replies now without starting a second,
    // unowned about:blank navigation in parallel with its finally block.
    _pageActive = false;
  }

  Future<void> _injectParser() async {
    if (!_pageActive || isVideoSourceLoaded) return;
    final session = _session;
    // onLoadStart can run against the previous about:blank document. Check
    // the current page and also guard inside the JS document itself.
    final url = await webviewController?.getUrl();
    if (!_pageActive ||
        session != _session ||
        url == null ||
        url.toString() == 'about:blank') {
      return;
    }
    await webviewController?.evaluateJavascript(
      source: legacyVideoParserScript(
          session: session, iframeOnly: useLegacyParser),
    );
  }

  Future<void> _tryPlayerCompat(
      WebResourceRequest request, WebResourceResponse response) async {
    final session = _session;
    final media = await _playerCompat.onHttpError(
        request.url.toString(), response.statusCode,
        requestHeaders: request.headers,
        method: request.method,
        isForMainFrame: request.isForMainFrame);
    if (media == null || !_pageActive || _disposed || session != _session) {
      return;
    }
    reportDiagnostic('legacy_player_compat', request.url.toString(),
        'matched HHJX bounded response');
    _resolve(media, 'Legacy player response');
  }

  void _startVideoParserTimer() {
    videoParserTimer?.cancel();
    videoParserTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_pageActive || isVideoSourceLoaded) {
        timer.cancel();
        return;
      }
      if (!_polling) {
        unawaited(_pollVideoSource());
      }
    });
  }

  Future<void> _pollVideoSource() async {
    _polling = true;
    final session = _session;
    try {
      if (_pageActive && !isVideoSourceLoaded) {
        // Normally the callbacks install the parser. A page that never reaches
        // onLoadStop still needs one installation; the idempotent script also
        // catches an early onLoadStart injection against the previous document.
        await _injectParser();
        if (_pageActive && session == _session && !isVideoSourceLoaded) {
          await webviewController?.evaluateJavascript(
              source: legacyVideoParserPollScript(session));
        }
      }
    } catch (error) {
      if (_pageActive && session == _session) {
        _log('Parser scan failed: $error');
      }
    } finally {
      _polling = false;
    }
  }

  @override
  Future<void> unloadPage() async {
    _playerCompat.cancel();
    _pageActive = false;
    _session++;
    videoParserTimer?.cancel();
    videoParserTimer = null;
    await webviewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri('about:blank')));
  }

  @override
  Future<void> captureParserSnapshot() async {
    if (!_pageActive) return;
    final session = _session;
    final value = await webviewController?.evaluateJavascript(
        source: videoParserSnapshotScript);
    if (!_pageActive || session != _session || value is! String) return;
    final data = jsonDecode(value) as Map<String, dynamic>;
    reportDiagnostic('dom_snapshot', '',
        'ready=${data['ready']} frames=${data['frames']} videos=${data['videos']} installed=${data['installed']} active=${data['active']}');
    for (final url in (data['urls'] as List).whereType<String>()) {
      reportDiagnostic('iframe_snapshot', url, '');
    }
  }

  @override
  Future<void> dispose() async {
    _playerCompat.cancel();
    _disposed = true;
    _pageActive = false;
    _session++;
    videoParserTimer?.cancel();
    videoParserTimer = null;
    await headlessWebView?.dispose();
    headlessWebView = null;
    webviewController = null;
    hasRegisteredHandlers = false;
    disposeEventControllers();
  }

  bool _isM3U8Url(String url) =>
      isVideoParserNetworkUrl(url) &&
      Uri.parse(url).path.toLowerCase().endsWith('.m3u8');

  bool _isRangeVideoRequest(String url, Map<String, String>? headers) {
    if (!isVideoParserNetworkUrl(url) || headers == null) return false;
    final range = headers['Range'] ?? headers['range'];
    if (range == null || !range.startsWith('bytes=')) return false;
    final path = Uri.parse(url).path.toLowerCase();
    return !RegExp(r'\.(js|css|html|json|png|jpg|gif|svg|woff2?|wasm)$')
        .hasMatch(path);
  }

  void _log(String message) {
    if (!logEventController.isClosed) logEventController.add(message);
  }

  Future<void> _setupProxy() async {
    final bool proxyEnable = GStorage.getSetting(SettingsKeys.proxyEnable);
    if (!proxyEnable) {
      return;
    }

    final String proxyUrl = GStorage.getSetting(SettingsKeys.proxyUrl);
    final formattedProxy = ProxyUtils.getFormattedProxyUrl(proxyUrl);
    if (formattedProxy == null) {
      return;
    }

    try {
      final proxyAvailable =
          await android_webview.AndroidWebViewFeature.instance()
              .isFeatureSupported(WebViewFeature.PROXY_OVERRIDE);
      if (!proxyAvailable) {
        KazumiLogger().w('WebView: 当前 Android 版本不支持代理');
        return;
      }

      final proxyController = android_webview.AndroidProxyController.instance();
      await proxyController.clearProxyOverride();
      await proxyController.setProxyOverride(
        settings: ProxySettings(
          proxyRules: [
            ProxyRule(url: formattedProxy),
          ],
        ),
      );
      KazumiLogger().i('WebView: 代理设置成功 $formattedProxy');
    } catch (e) {
      KazumiLogger().e('WebView: 设置代理失败 $e');
    }
  }
}
