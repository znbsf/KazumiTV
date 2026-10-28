import 'dart:io';
import 'package:kazumi/services/logging/logger.dart';

import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

class WebViewFeatureService {
  WebViewFeatureService._();

  static bool? _isDocumentStartScriptSupported;
  static Future<void>? _initialization;

  static Future<void> initialize() => _initialization ??= _initialize();

  static Future<void> _initialize() async {
    if (Platform.isAndroid) {
      try {
        _isDocumentStartScriptSupported = await PlatformWebViewFeature.static()
            .isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)
            .timeout(const Duration(seconds: 3));
      } catch (error) {
        _isDocumentStartScriptSupported = false;
        KazumiLogger().w(
            'WebView feature probe unavailable; using fallback parser',
            error: error);
      }
    }
  }

  static bool get isDocumentStartScriptSupported =>
      _isDocumentStartScriptSupported ?? false;
}
