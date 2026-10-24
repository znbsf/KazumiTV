import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/platform/webview_feature_service.dart';

void main() {
  test('QA Gecko keeps its verified provider scope, independently of HHJX', () {
    for (final provider in [
      'com.android.webview',
      'com.google.android.webview'
    ]) {
      expect(WebViewFeatureService.needsPlayerCompat(provider, '66.0.3359.158'),
          isTrue);
      for (final version in [
        null,
        '',
        '65.0.0.0',
        '67.0.0.0',
        '141.0.0.0',
        '66.0.bad',
        'Chrome/66.0.3359.158'
      ]) {
        expect(WebViewFeatureService.needsPlayerCompat(provider, version),
            isFalse);
      }
    }
    for (final provider in [null, '', 'vendor.webview', 'com.android.chrome']) {
      expect(WebViewFeatureService.needsPlayerCompat(provider, '66.0.3359.158'),
          isFalse);
    }
  });
}
