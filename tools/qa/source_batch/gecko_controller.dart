import 'package:flutter/services.dart';
import 'package:kazumi/webview/video/video_webview_controller.dart';
import 'package:kazumi/webview/video/video_parser_url.dart';

const qaChannel = MethodChannel('kazumi/parser_qa');

class GeckoQaController extends VideoWebviewController<dynamic> {
  GeckoQaController(this.userAgent);
  final String userAgent;
  int _generation = 0;
  bool _active = false;

  @override
  Future<void> init() async {
    qaChannel.setMethodCallHandler((call) async {
      if (!_active) return;
      final args = Map<String, dynamic>.from(call.arguments as Map);
      if (args['generation'] != _generation) return;
      if (call.method == 'geckoDiagnostic') {
        reportDiagnostic(args['stage'] as String, args['url'] as String, args['detail'] as String);
        return;
      }
      if (call.method != 'geckoEvent') return;
      final raw = args['url'] as String;
      if (args['handler'] == 'JSBridgeDebug') {
        final media = embeddedVideoParserUrl(raw);
        if (media != null) { notifyVideoSourceResolved(media); return; }
        final page = nestedVideoPageUrl(raw, fromPlayerQuery: true);
        if (page != null) notifyNestedPageCandidate(page);
      } else {
        final page = nestedVideoPageUrl(raw);
        if (page != null) { notifyNestedPageCandidate(page); return; }
        if (isVideoParserNetworkUrl(raw) && !isVideoParserAdUrl(raw)) {
          notifyVideoSourceResolved(raw);
        }
      }
    });
    await qaChannel.invokeMethod<void>('geckoInit');
    initEventController.add(true);
  }

  @override
  Future<void> loadUrl(String url, bool useLegacyParser, {int offset = 0}) async {
    // Deliberately explicit prototype limitation; never silently change modes.
    if (useLegacyParser) throw UnsupportedError('Gecko QA iframe-only mode');
    await unloadPage();
    this.offset = offset;
    _active = true;
    await qaChannel.invokeMethod<void>('geckoLoad', {
      'url': url, 'ua': userAgent, 'generation': _generation,
    });
  }

  @override
  Future<void> unloadPage() async {
    _active = false;
    _generation++;
    await qaChannel.invokeMethod<void>('geckoClose');
  }

  @override
  Future<void> dispose() async {
    await unloadPage();
    qaChannel.setMethodCallHandler(null);
    disposeEventControllers();
  }
}
