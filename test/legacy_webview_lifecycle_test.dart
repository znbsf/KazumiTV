import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:kazumi/services/video_source/webview_video_source_service.dart';
import 'package:kazumi/webview/video/impl/video_webview_impl.dart';
import 'package:kazumi/webview/video/video_webview_controller.dart';

void main() {
  const iframe = 'https://site.example/player/index.html?url='
      'https://media.example/episode/index.m3u8';
  late VideoWebviewImpl parser;
  late _Controller controller;
  late List<VideoParserEvent> events;
  late StreamSubscription<VideoParserEvent> subscription;

  setUp(() {
    parser = _InitializedParser();
    controller = _Controller();
    parser.webviewController = controller;
    events = [];
    subscription = parser.onVideoURLParser.listen(events.add);
  });
  tearDown(() async {
    await subscription.cancel();
    await parser.dispose();
  });

  test('ordinary mode resolves an iframe query without running its player',
      () async {
    await parser.loadUrl('https://site.example/episode/1', false, offset: 42);
    controller.reply('JSBridgeDebug', [iframe, 1]);
    controller.reply('JSBridgeDebug', [iframe, 1]);
    await Future<void>.delayed(Duration.zero);
    expect(events.map((event) => event.url),
        ['https://media.example/episode/index.m3u8']);
    expect(events.single.offset, 42);
    expect(controller.urls, ['about:blank', 'https://site.example/episode/1']);
    expect(parser.videoParserTimer, isNull);
    await parser.unloadPage();
    expect(controller.urls,
        ['about:blank', 'https://site.example/episode/1', 'about:blank']);
  });

  test('reusing one WebView can switch both parser modes', () async {
    await parser.loadUrl('https://site.example/episode/1', true);
    controller
        .reply('VideoBridgeDebug', ['https://media.example/incorrect.mp4', 1]);
    expect(events, isEmpty);
    await parser.loadUrl('https://site.example/episode/2', false, offset: 17);
    controller.reply('VideoBridgeDebug', ['https://media.example/2.mp4', 2]);
    await Future<void>.delayed(Duration.zero);
    expect(events.single.url, 'https://media.example/2.mp4');
    expect(controller.registrations,
        {'LogBridge': 1, 'JSBridgeDebug': 1, 'VideoBridgeDebug': 1});
    await parser.loadUrl('https://site.example/episode/3', true);
    controller.reply('JSBridgeDebug', [iframe, 3]);
    await Future<void>.delayed(Duration.zero);
    expect(events.length, 2);
  });

  test('old replies are ignored after unload, replacement, and disposal',
      () async {
    await parser.loadUrl('https://site.example/episode/1', false);
    await parser.unloadPage();
    controller.reply('VideoBridgeDebug', ['https://media.example/old.mp4', 1]);
    await parser.loadUrl('https://site.example/episode/2', false);
    controller.reply('JSBridgeDebug', [iframe, 1]);
    controller.reply('VideoBridgeDebug', ['https://media.example/old.mp4', 1]);
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
    controller
        .reply('VideoBridgeDebug', ['https://media.example/current.mp4', 3]);
    await Future<void>.delayed(Duration.zero);
    expect(events.single.url, 'https://media.example/current.mp4');
    await parser.dispose();
    expect(
        () => controller.reply('JSBridgeDebug', [iframe, 3]), returnsNormally);
  });

  test(
      'malformed, nonmedia, blob, advertisement and untagged replies stay unresolved',
      () async {
    await parser.loadUrl('https://site.example/episode/1', false);
    for (final candidate in [
      'https://site.example/player?url=https://media.example/page.html',
      'https://site.example/player?url=https://googleads.example/ad.mp4',
      'https://site.example/player?url=javascript:alert(1)',
      'https://site.example/player?url=%',
      'blob:https://site.example/id',
    ]) {
      expect(() => controller.reply('JSBridgeDebug', [candidate, 1]),
          returnsNormally);
    }
    controller.reply('JSBridgeDebug', [iframe]);
    controller.reply('VideoBridgeDebug', ['blob:https://site.example/id', 1]);
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
  });

  test('embedded signed media query keeps its escaped token and all parameters',
      () async {
    await parser.loadUrl('https://site.example/episode/1', false);
    const media = 'https://media.example/1.m3u8?token=a%2Fb%26c&expires=123';
    final page =
        Uri.https('site.example', '/player', {'url': media}).toString();
    controller.reply('JSBridgeDebug', [page, 1]);
    await Future<void>.delayed(Duration.zero);
    expect(events.single.url, media);
  });

  test('service awaits one retirement before reusing the fallback parser',
      () async {
    const firstPage = 'https://site.example/episode/1';
    const secondPage = 'https://site.example/episode/2';
    final service = WebViewVideoSourceService(controllerFactory: () => parser);
    final firstLoaded = Completer<void>();
    final secondLoaded = Completer<void>();
    final cleanupEntered = Completer<void>();
    final finishCleanup = Completer<void>();
    var blanks = 0;
    controller.onLoad = (url) async {
      if (url == 'about:blank') {
        blanks++;
        if (blanks == 2) {
          cleanupEntered.complete();
          await finishCleanup.future;
        }
      } else if (url == firstPage) {
        firstLoaded.complete();
      } else if (url == secondPage) {
        secondLoaded.complete();
      }
    };
    addTearDown(() async {
      if (!finishCleanup.isCompleted) finishCleanup.complete();
      await service.dispose();
    });

    final first = service.resolve(firstPage, useLegacyParser: false);
    await firstLoaded.future;
    controller.reply('JSBridgeDebug', [iframe, 1]);
    await cleanupEntered.future;
    expect(blanks, 2); // initial blank plus one service-owned retirement
    expect(parser.videoParserTimer, isNull);

    final second = service.resolve(secondPage, useLegacyParser: false);
    await Future<void>.delayed(Duration.zero);
    expect(secondLoaded.isCompleted, isFalse);
    finishCleanup.complete();
    expect((await first).url, 'https://media.example/episode/index.m3u8');
    await secondLoaded.future;
    await Future<void>.delayed(Duration.zero);
    expect(controller.urls,
        ['about:blank', firstPage, 'about:blank', 'about:blank', secondPage]);

    controller.reply('VideoBridgeDebug', ['https://media.example/old.mp4', 1]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.urls.last, secondPage);
    controller.reply('VideoBridgeDebug', ['https://media.example/2.mp4', 3]);
    expect((await second).url, 'https://media.example/2.mp4');
    expect(controller.urls, [
      'about:blank',
      firstPage,
      'about:blank',
      'about:blank',
      secondPage,
      'about:blank'
    ]);
    expect(blanks, 4);
  });

  testWidgets('polling cannot inject into blank pages and does not overlap',
      (tester) async {
    await parser.loadUrl('https://site.example/episode/1', false);
    controller.url = WebUri('about:blank');
    await tester.pump(const Duration(seconds: 1));
    expect(
        controller.scripts.where((script) => script.contains('var session =')),
        isEmpty);
    controller.url = WebUri('https://site.example/episode/1');
    final blocker = Completer<dynamic>();
    controller.blocker = blocker;
    await tester.pump(const Duration(seconds: 1));
    final calls = controller.scripts.length;
    await tester.pump(const Duration(seconds: 3));
    expect(controller.scripts.length, calls);
    await parser.unloadPage();
    blocker.complete(null);
    await tester.pump();
    expect(controller.scripts.length, calls);
  });
}

class _InitializedParser extends VideoWebviewImpl {
  @override
  Future<void> init() async {}
}

class _Controller implements PlatformInAppWebViewController {
  final Map<String, JavaScriptHandlerCallback> handlers = {};
  final Map<String, int> registrations = {};
  final List<String> urls = [];
  final List<String> scripts = [];
  WebUri? url;
  Completer<dynamic>? blocker;
  Future<void> Function(String)? onLoad;

  void reply(String name, List<dynamic> args) => handlers[name]!(args);

  @override
  void addJavaScriptHandler(
      {required String handlerName,
      required JavaScriptHandlerCallback callback}) {
    handlers[handlerName] = callback;
    registrations.update(handlerName, (value) => value + 1, ifAbsent: () => 1);
  }

  @override
  Future<void> loadUrl(
      {required URLRequest urlRequest,
      Uri? iosAllowingReadAccessTo,
      WebUri? allowingReadAccessTo}) async {
    url = urlRequest.url;
    urls.add(url.toString());
    await onLoad?.call(url.toString());
  }

  @override
  Future<WebUri?> getUrl() async => url;

  @override
  Future<dynamic> evaluateJavascript(
      {required String source, ContentWorld? contentWorld}) async {
    scripts.add(source);
    return blocker?.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
