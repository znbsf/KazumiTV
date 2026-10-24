import 'dart:convert';
import 'dart:async';
import 'package:kazumi/services/video_source/legacy_player_compat.dart';
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
  VideoWebviewAndroidImpl({LegacyPlayerCompat? playerCompat})
      : _playerCompat = playerCompat ?? LegacyPlayerCompat();
  final LegacyPlayerCompat _playerCompat;
  bool _compatInterception = false;
  static const _parserScriptGroup = 'kazumi-video-parser';
  PlatformHeadlessInAppWebView? headlessWebView;
  bool _hasRegisteredHandlers = false;
  bool _useLegacyParser = false;
  bool _pageActive = false;
  int _session = 0;
  bool _disposed = false;

  @override
  Future<void> init() async {
    await _setupProxy();
    if (_disposed) return;
    headlessWebView ??= PlatformHeadlessInAppWebView(
      PlatformHeadlessInAppWebViewCreationParams(
        initialSettings: InAppWebViewSettings(
          userAgent: getRandomUA(),
          mediaPlaybackRequiresUserGesture: true,
          cacheEnabled: false,
          // Only the scoped episode enables native observation during loading.
          useShouldInterceptRequest: false,
          blockNetworkImage: true,
          loadsImagesAutomatically: false,
          upgradeKnownHostsToHTTPS: false,
          safeBrowsingEnabled: false,
          mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
          geolocationEnabled: false,
        ),
        onWebViewCreated: (controller) {
          if (_disposed) return;
          KazumiLogger().i('[WebView] Created');
          webviewController = controller;
          initEventController.add(true);
        },
        shouldInterceptRequest: (controller, request) async {
          if (_pageActive && !isVideoSourceLoaded && _compatInterception) {
            _playerCompat.observePage(request.url.toString(), request.headers);
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
        onReceivedError: (controller, request, error) {
          if (_pageActive) {
            reportDiagnostic('resource_error', request.url.toString(),
                'code=${error.type.toNativeValue()} mainFrame=${request.isForMainFrame} ${error.description}');
          }
        },
        onLoadStart: (controller, url) async {
          _log('started loading: $url');
          if (_pageActive) reportDiagnostic('load_start', '$url', '');
        },
        onLoadStop: (controller, url) {
          _log('loading completed: $url');
          if (_pageActive) reportDiagnostic('load_stop', '$url', '');
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
    final observe = !useLegacyParser && LegacyPlayerCompat.supportsEpisode(url);
    if (_compatInterception != observe) {
      await webviewController?.setSettings(
          settings: InAppWebViewSettings(useShouldInterceptRequest: observe));
      _compatInterception = observe;
    }
    _playerCompat.begin(url, enabled: observe);
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
        if (url != null) {
          _resolve(url);
        } else if (nestedVideoPageUrl(args[0].toString(), fromPlayerQuery: true)
            case final page?) {
          notifyNestedPageCandidate(page);
        }
      },
    );
    webviewController?.addJavaScriptHandler(
      handlerName: 'VideoBridgeDebug',
      callback: (args) {
        if (!_isCurrentReply(args) || _useLegacyParser) return;
        final url = args[0].toString();
        if (nestedVideoPageUrl(url) case final page?) {
          notifyNestedPageCandidate(page);
          return;
        }
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
    _playerCompat.cancel();
    isIframeLoaded = true;
    isVideoSourceLoaded = true;
    _pageActive = false;
    videoLoadingEventController.add(false);
    _log('Loading video source: $url');
    notifyVideoSourceResolved(url);
    // The source service owns and awaits page retirement before reuse.
    // Starting a second, unawaited about:blank here can clear the next page.
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
    _resolve(media);
  }

  @override
  Future<void> unloadPage() async {
    _playerCompat.cancel();
    _pageActive = false;
    _session++;
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
