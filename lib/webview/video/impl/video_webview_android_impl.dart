import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/network/proxy_utils.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/webview/video/video_webview_controller.dart';
import 'package:kazumi/webview/video/legacy_parser_scripts.dart';
import 'package:kazumi/webview/video/video_parser_url.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_inappwebview_android/flutter_inappwebview_android.dart'
    as android_webview;
import 'package:kazumi/utils/http_headers.dart';

class VideoWebviewAndroidImpl
    extends VideoWebviewController<PlatformInAppWebViewController> {
  static const _parserScriptGroup = 'kazumi-video-parser';
  PlatformHeadlessInAppWebView? headlessWebView;
  bool _hasRegisteredHandlers = false;
  bool _useLegacyParser = false;
  bool _pageActive = false;
  int _session = 0;

  @override
  Future<void> init() async {
    await _setupProxy();
    headlessWebView ??= PlatformHeadlessInAppWebView(
      PlatformHeadlessInAppWebViewCreationParams(
        initialSettings: InAppWebViewSettings(
          userAgent: getRandomUA(),
          mediaPlaybackRequiresUserGesture: true,
          cacheEnabled: false,
          blockNetworkImage: true,
          loadsImagesAutomatically: false,
          upgradeKnownHostsToHTTPS: false,
          safeBrowsingEnabled: false,
          mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
          geolocationEnabled: false,
        ),
        onWebViewCreated: (controller) {
          KazumiLogger().i('[WebView] Created');
          webviewController = controller;
          initEventController.add(true);
        },
        onLoadStart: (controller, url) async {
          _log('started loading: $url');
        },
        onLoadStop: (controller, url) {
          _log('loading completed: $url');
        },
      ),
    );
    await headlessWebView?.run();
  }

  @override
  Future<void> loadUrl(String url, bool useLegacyParser,
      {int offset = 0}) async {
    await unloadPage();
    if (!_hasRegisteredHandlers) {
      _addJavaScriptHandlers();
      _hasRegisteredHandlers = true;
    }
    // A pooled WebView serves different rules, and old documents can reply
    // after navigation. Replace only our scripts with this request's mode
    // and generation; Dart callbacks alone cannot identify an old document.
    await webviewController?.removeUserScriptsByGroupName(
        groupName: _parserScriptGroup);
    await webviewController?.addUserScripts(userScripts: [
      UserScript(
        groupName: _parserScriptGroup,
        source: legacyVideoParserScript(
            session: _session, iframeOnly: useLegacyParser),
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    ]);
    count = 0;
    this.offset = offset;
    _useLegacyParser = useLegacyParser;
    isIframeLoaded = false;
    isVideoSourceLoaded = false;
    _pageActive = true;
    videoLoadingEventController.add(true);
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
    webviewController?.addJavaScriptHandler(
      handlerName: 'JSBridgeDebug',
      callback: (args) {
        if (!_isCurrentReply(args)) return;
        final url = embeddedVideoParserUrl(args[0].toString());
        if (url != null) _resolve(url);
      },
    );
    webviewController?.addJavaScriptHandler(
      handlerName: 'VideoBridgeDebug',
      callback: (args) {
        if (!_isCurrentReply(args) || _useLegacyParser) return;
        final url = args[0].toString();
        if (isVideoParserNetworkUrl(url) && !isVideoParserAdUrl(url)) {
          _resolve(url);
        }
      },
    );
  }

  bool _isCurrentReply(List<dynamic> args) =>
      _pageActive &&
      !isVideoSourceLoaded &&
      args.length >= 2 &&
      args[1] == _session;

  void _resolve(String url) {
    isIframeLoaded = true;
    isVideoSourceLoaded = true;
    _pageActive = false;
    videoLoadingEventController.add(false);
    _log('Loading video source: $url');
    notifyVideoSourceResolved(url);
    // The source service owns and awaits page retirement before reuse.
    // Starting a second, unawaited about:blank here can clear the next page.
  }

  @override
  Future<void> unloadPage() async {
    _pageActive = false;
    _session++;
    await webviewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri('about:blank')));
  }

  @override
  Future<void> dispose() async {
    _pageActive = false;
    _session++;
    await headlessWebView?.dispose();
    headlessWebView = null;
    webviewController = null;
    _hasRegisteredHandlers = false;
    disposeEventControllers();
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
