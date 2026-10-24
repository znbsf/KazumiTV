import 'dart:io';

import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

class WebViewFeatureService {
  WebViewFeatureService._();

  static bool? _isDocumentStartScriptSupported;
  static bool _needsLegacyPlayerCompat = false;

  // Only the provider/version reproduced on the TV is enabled. Unknown and
  // modern engines fail closed; never infer engine capabilities from a UA.
  static bool needsPlayerCompat(String? packageName, String? versionName) =>
      const {'com.android.webview', 'com.google.android.webview'}
          .contains(packageName) &&
      RegExp(r'^66\.\d+\.\d+\.\d+$').hasMatch(versionName ?? '');

  static bool get needsLegacyPlayerCompat => _needsLegacyPlayerCompat;

  static Future<void> initialize() async {
    if (Platform.isAndroid) {
      _isDocumentStartScriptSupported = await PlatformWebViewFeature.static()
          .isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT);
      try {
        final provider = await PlatformInAppWebViewController.static()
            .getCurrentWebViewPackage();
        _needsLegacyPlayerCompat =
            needsPlayerCompat(provider?.packageName, provider?.versionName);
      } catch (_) {
        _needsLegacyPlayerCompat = false;
      }
    }
  }

  static bool get isDocumentStartScriptSupported =>
      _isDocumentStartScriptSupported ?? false;
}
