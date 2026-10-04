import 'dart:async';

import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/webview/video/impl/video_webview_android_impl.dart';
import 'package:kazumi/webview/video/video_webview_controller.dart';

const _iframe = 'https://site.example/player?url='
    'https://media.example/1.m3u8';

void main() {
  late VideoWebviewAndroidImpl parser;
  late _Controller controller;
  late List<VideoParserEvent> events;
  late StreamSubscription<VideoParserEvent> subscription;

  setUp(() {
    parser = VideoWebviewAndroidImpl();
    controller = _Controller();
    parser.webviewController = controller;
    events = [];
    subscription = parser.onVideoURLParser.listen(events.add);
  });
  tearDown(() async {
    await subscription.cancel();
    await parser.dispose();
  });

  for (final firstLegacy in [true, false]) {
    test('pooled Android parser switches modes from $firstLegacy and back',
        () async {
      for (var i = 0; i < 3; i++) {
        final legacy = i.isEven ? firstLegacy : !firstLegacy;
        await parser.loadUrl('https://site.example/episode/${i + 1}', legacy,
            offset: i * 10);
        controller.reply(legacy ? 'JSBridgeDebug' : 'VideoBridgeDebug',
            [legacy ? _iframe : 'https://media.example/2.mp4', i + 1]);
        await Future<void>.delayed(Duration.zero);
        expect(events.length, i + 1);
        expect(
            events.last.url,
            legacy
                ? 'https://media.example/1.m3u8'
                : 'https://media.example/2.mp4');
        expect(events.last.offset, i * 10);
      }
    });
  }

  test('late document reply cannot resolve the next episode with its offset',
      () async {
    await parser.loadUrl('https://site.example/episode/1', false, offset: 10);
    final oldReply = controller.handlers['VideoBridgeDebug']!;
    await parser.loadUrl('https://site.example/episode/2', false, offset: 20);
    oldReply(['https://media.example/old.mp4', 1]);
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
    controller
        .reply('VideoBridgeDebug', ['https://media.example/current.mp4', 2]);
    await Future<void>.delayed(Duration.zero);
    expect(events.single.url, 'https://media.example/current.mp4');
    expect(events.single.offset, 20);
    // The source service, not a fire-and-forget bridge callback, retires pages.
    expect(controller.urls, [
      'about:blank',
      'https://site.example/episode/1',
      'about:blank',
      'https://site.example/episode/2',
    ]);
  });

  test('embedded signed URL retains original escaped query bytes', () async {
    await parser.loadUrl('https://site.example/episode/1', true);
    const media = 'https://media.example/1.m3u8?token=a%2Fb%26c&expires=123';
    final iframe =
        Uri.https('site.example', '/player', {'url': media}).toString();
    controller.reply('JSBridgeDebug', [iframe, 1]);
    await Future<void>.delayed(Duration.zero);
    expect(events.single.url, media);
  });

  test('unload and disposal invalidate all old replies', () async {
    await parser.loadUrl('https://site.example/episode/1', false);
    await parser.unloadPage();
    controller.reply('VideoBridgeDebug', ['https://media.example/old.mp4', 1]);
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
    await parser.dispose();
    expect(
        () => controller
            .reply('VideoBridgeDebug', ['https://media.example/old.mp4', 1]),
        returnsNormally);
  });

  test('invalid and wrong-mode bridge messages cannot complete a request',
      () async {
    await parser.loadUrl('https://site.example/episode/1', true);
    for (final args in <List<dynamic>>[
      [],
      [_iframe],
      [_iframe, 0],
      ['https://site.example/player?url=%', 1],
      ['https://site.example/player?url=https://googleads.example/ad.mp4', 1],
      ['https://site.example/player?url=https://media.example/index.html', 1],
    ]) {
      expect(() => controller.reply('JSBridgeDebug', args), returnsNormally);
    }
    controller
        .reply('VideoBridgeDebug', ['https://media.example/wrong.mp4', 1]);
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
  });

  test('scripts replace only owned group and carry current mode and session',
      () async {
    final unrelated = UserScript(
        source: 'unrelated()',
        groupName: 'unrelated',
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START);
    controller.scripts.add(unrelated);
    await parser.loadUrl('https://site.example/episode/1', true);
    await parser.loadUrl('https://site.example/episode/2', false);
    expect(controller.scripts, contains(same(unrelated)));
    final owned = controller.scripts.where((script) => script != unrelated);
    expect(owned, hasLength(1));
    expect(
        owned.single.injectionTime, UserScriptInjectionTime.AT_DOCUMENT_START);
    expect(owned.single.source, contains('var session = 2;'));
    expect(owned.single.source, contains('iframeOnly: false'));
  });
}

class _Controller implements PlatformInAppWebViewController {
  final handlers = <String, JavaScriptHandlerCallback>{};
  final urls = <String>[];
  final scripts = <UserScript>[];

  void reply(String name, List<dynamic> args) {
    final handler = handlers[name];
    expect(handler, isNotNull,
        reason: 'Missing bridge $name after parser reuse');
    handler?.call(args);
  }

  @override
  void addJavaScriptHandler(
          {required String handlerName,
          required JavaScriptHandlerCallback callback}) =>
      handlers[handlerName] = callback;

  @override
  Future<void> loadUrl(
      {required URLRequest urlRequest,
      Uri? iosAllowingReadAccessTo,
      WebUri? allowingReadAccessTo}) async {
    urls.add(urlRequest.url.toString());
  }

  @override
  Future<void> addUserScripts({required List<UserScript> userScripts}) async {
    scripts.addAll(userScripts);
  }

  @override
  Future<void> removeUserScriptsByGroupName({required String groupName}) async {
    scripts.removeWhere((script) => script.groupName == groupName);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
