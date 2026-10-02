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
import 'package:kazumi/utils/media.dart';
import 'package:kazumi/utils/http_headers.dart';

class VideoWebviewImpl
    extends VideoWebviewController<PlatformInAppWebViewController> {
  PlatformHeadlessInAppWebView? headlessWebView;
  bool hasRegisteredHandlers = false;
  bool useLegacyParser = false;
  Timer? videoParserTimer;
  int _session = 0;
  bool _pageActive = false;
  bool _polling = false;

  @override
  Future<void> init() async {
    await _setupProxy();
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
          KazumiLogger().i('[WebView] Created (legacy fallback)');
          webviewController = controller;
          initEventController.add(true);
        },
        shouldInterceptRequest: (controller, request) async {
          if (!_pageActive || isVideoSourceLoaded) return null;
          final url = request.url.toString();
          if (_isAdUrl(url)) return null;
          // An iframe's public query can expose the media URL before its
          // JavaScript player fails on an older WebView. Reuse the existing
          // legacy decoder in both modes; no page code or authentication is
          // changed, and cross-origin documents remain inaccessible.
          final embedded = _embeddedMediaUrl(url);
          if (embedded != null) {
            _resolve(embedded, 'Native intercepted embedded video URL');
          } else if (!useLegacyParser &&
              (_isM3U8Url(url) || _isRangeVideoRequest(url, request.headers))) {
            _resolve(url, 'Native intercepted video URL');
          }
          return null;
        },
        onLoadStart: (controller, url) async {
          _log('started loading: $url');
          if (url.toString() != 'about:blank') await _injectParser();
        },
        onLoadStop: (controller, url) async {
          _log('loading completed: $url');
          if (url.toString() != 'about:blank') await _injectParser();
        },
        onConsoleMessage: (controller, consoleMessage) {
          _log(
              'Console [${consoleMessage.messageLevel}]: ${consoleMessage.message}');
        },
        onReceivedError: (controller, request, error) {
          _log('Error: ${error.description} - ${request.url}');
        },
      ),
    );
    await headlessWebView?.run();
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
        final url = _embeddedMediaUrl(args[0].toString());
        if (url != null) _resolve(url, 'Iframe embedded video URL');
      },
    );
    webviewController?.addJavaScriptHandler(
      handlerName: 'VideoBridgeDebug',
      callback: (args) {
        if (!_isCurrentReply(args) || useLegacyParser) return;
        final url = args[0].toString();
        if (_isNetworkUrl(url) && !_isAdUrl(url)) {
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
    _pageActive = false;
    _session++;
    videoParserTimer?.cancel();
    videoParserTimer = null;
    await webviewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri('about:blank')));
  }

  @override
  Future<void> dispose() async {
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

  String? _embeddedMediaUrl(String source) {
    if (!_isNetworkUrl(source) || _isAdUrl(source)) return null;
    try {
      final encoded = Uri.encodeFull(source);
      final extracted = decodeVideoSource(encoded);
      if (extracted == encoded) return null;
      // decodeVideoSource applies encodeFull to its extracted value. Undo
      // exactly that outer encoding, then let Uri preserve already escaped
      // query bytes: signed token a%2Fb must not become a%252Fb.
      final decoded = Uri.parse(Uri.decodeFull(extracted)).toString();
      if (!_isNetworkUrl(decoded) || _isAdUrl(decoded)) {
        return null;
      }
      final path = Uri.parse(decoded).path.toLowerCase();
      if (!path.endsWith('.m3u8') && !path.endsWith('.mp4')) return null;
      return decoded;
    } on FormatException {
      return null;
    }
  }

  bool _isNetworkUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  bool _isM3U8Url(String url) =>
      _isNetworkUrl(url) && Uri.parse(url).path.toLowerCase().endsWith('.m3u8');

  bool _isRangeVideoRequest(String url, Map<String, String>? headers) {
    if (!_isNetworkUrl(url) || headers == null) return false;
    final range = headers['Range'] ?? headers['range'];
    if (range == null || !range.startsWith('bytes=')) return false;
    final path = Uri.parse(url).path.toLowerCase();
    return !RegExp(r'\.(js|css|html|json|png|jpg|gif|svg|woff2?|wasm)$')
        .hasMatch(path);
  }

  bool _isAdUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('googleads') ||
        lower.contains('googlesyndication') ||
        lower.contains('adtrafficquality') ||
        lower.contains('doubleclick') ||
        lower.contains('prestrain.html') ||
        lower.contains('prestrain%2ehtml');
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
