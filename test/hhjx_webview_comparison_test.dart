// Controlled production callback comparison, not real WebView binary testing.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/video_source/legacy_player_compat.dart';
import 'package:kazumi/webview/video/impl/video_webview_android_impl.dart';
import 'package:kazumi/webview/video/impl/video_webview_impl.dart';
import 'package:kazumi/webview/video/video_webview_controller.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

const _episode = 'https://dmbus.cc/p/6330-1-2.html';
const _ordinary = 'https://ordinary.example/episode/2';
const _media = 'https://media.example/video.mp4';
final _encoded = 'ab' * 32;
final _iframe = '${LegacyPlayerCompat.origin}/?url=$_encoded';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('hhjx-callback-comparison-');
    PathProviderPlatform.instance = _Paths(temp.path);
    Hive.init(temp.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  for (final modern in [false, true]) {
    final pipeline = modern
        ? 'document-start production pipeline'
        : 'polling production pipeline';
    group(pipeline, () {
      late _Harness h;
      setUp(() async {
        h = await _Harness.open(modern);
      });
      tearDown(() async {
        await h.dispose();
      });

      test('confirmed null-Origin POST 403 resolves once with current iframe',
          () async {
        await h.observe();
        h.fail();
        expect(await h.resolved.future.timeout(const Duration(seconds: 2)),
            _media);
        expect(h.transport.requests.map((r) => r.method), ['GET', 'POST']);
        expect(h.transport.requests.last.headers['Origin'],
            LegacyPlayerCompat.origin);
        expect(h.transport.requests.last.headers['Referer'], _iframe);
        expect(h.transport.requests.last.followRedirects, false);
        h.fail();
        await h.flush();
        expect(h.events, hasLength(1));
        expect(h.transport.requests, hasLength(2));
      });

      test('normal successful media suppresses a later failure callback',
          () async {
        await h.observe();
        h.controller.reply('VideoBridgeDebug', [_media, 1]);
        expect(await h.resolved.future, _media);
        h.fail();
        await h.flush();
        expect(h.transport.requests, isEmpty);
      });

      test('unrelated or successful HTTP callbacks do not invoke adapter',
          () async {
        await h.observe();
        h.fail(status: 200);
        h.fail(status: 500);
        h.fail(url: 'https://other.example/api/parse');
        h.fail(url: '${LegacyPlayerCompat.endpoint}?extra=1');
        await h.flush();
        expect(h.transport.requests, isEmpty);
        expect(h.events, isEmpty);
      });

      test('missing or non-null Origin, method and frame ambiguity fail closed',
          () async {
        await h.observe();
        for (final headers in <Map<String, String>?>[
          null,
          {},
          {'Origin': LegacyPlayerCompat.origin},
          {'Origin': 'https://unrelated.example'},
          {'Origin': 'null', 'Cookie': 'synthetic'},
          {'Origin': 'null', 'Authorization': 'synthetic'},
          {'Origin': 'null', 'origin': LegacyPlayerCompat.origin},
          {'Origin': 'null', 'Referer': 'https://wrong.example/'},
        ]) {
          h.fail(headers: headers);
        }
        h.fail(method: 'GET');
        h.fail(method: null);
        h.fail(mainFrame: true);
        h.fail(mainFrame: null);
        await h.flush();
        expect(h.transport.requests, isEmpty);
      });

      test('old episode referrer and conflicting iframe never start requests',
          () async {
        await h.observe(referer: 'https://dmbus.cc/p/6330-1-3.html');
        h.fail();
        await h.flush();
        expect(h.transport.requests, isEmpty);
        await h.observe();
        await h.observe(url: '${LegacyPlayerCompat.origin}/?url=${'cd' * 32}');
        h.fail();
        await h.flush();
        expect(h.transport.requests, isEmpty);
      });

      test('iframe-only mode never gains a new request strategy', () async {
        await h.parser.loadUrl(_episode, true);
        await h.observe();
        h.fail();
        await h.flush();
        expect(h.transport.requests, isEmpty);
      });

      test('unload cancels in-flight POST and discards the late response',
          () async {
        final entered = Completer<void>(), response = Completer<ResponseBody>();
        h.transport.post = (_) {
          entered.complete();
          return response.future;
        };
        await h.observe();
        h.fail();
        await entered.future.timeout(const Duration(seconds: 2));
        await h.parser.unloadPage();
        response.complete(ResponseBody.fromString(
            jsonEncode({'code': 200, 'url': _media}), 200));
        await h.flush();
        expect(h.events, isEmpty);
        expect(h.transport.requests.last.cancelToken!.isCancelled, true);
      });

      test('primary media wins while the bounded adapter is pending', () async {
        final entered = Completer<void>(), response = Completer<ResponseBody>();
        h.transport.post = (_) {
          entered.complete();
          return response.future;
        };
        await h.observe();
        h.fail();
        await entered.future.timeout(const Duration(seconds: 2));
        h.controller.reply('VideoBridgeDebug', [_media, 1]);
        expect(await h.resolved.future, _media);
        response.complete(ResponseBody.fromString(
            jsonEncode({'code': 200, 'url': 'https://late.example/other.mp4'}),
            200));
        await h.flush();
        expect(h.events, hasLength(1));
      });

      if (modern) {
        test('native observation is scoped and disabled for other sources',
            () async {
          expect(
              h.platform.view.params.initialSettings!.useShouldInterceptRequest,
              false);
          expect(h.controller.interception, [true]);
          await h.parser.loadUrl(_ordinary, false);
          expect(h.controller.interception, [true, false]);
          await h.observe();
          h.fail();
          await h.flush();
          expect(h.transport.requests, isEmpty);
          await h.parser.loadUrl('https://ordinary.example/episode/3', false);
          expect(h.controller.interception, [true, false]);
        });
      }
    });
  }
}

class _Harness {
  _Harness(this.parser, this.platform, this.transport);
  final VideoWebviewController parser;
  final _Platform platform;
  final _Transport transport;
  final events = <VideoParserEvent>[];
  final resolved = Completer<String>();
  late StreamSubscription<VideoParserEvent> subscription;
  _Controller get controller => platform.view.controller;
  static Future<_Harness> open(bool modern) async {
    final platform = _Platform();
    InAppWebViewPlatform.instance = platform;
    final transport = _Transport();
    final compat =
        LegacyPlayerCompat(client: Dio()..httpClientAdapter = transport);
    final VideoWebviewController parser = modern
        ? VideoWebviewAndroidImpl(playerCompat: compat)
        : VideoWebviewImpl(playerCompat: compat);
    final h = _Harness(parser, platform, transport);
    h.subscription = parser.onVideoURLParser.listen((event) {
      h.events.add(event);
      if (!h.resolved.isCompleted) h.resolved.complete(event.url);
    });
    await parser.init();
    await parser.loadUrl(_episode, false);
    return h;
  }

  Future<void> observe({String? url, String referer = _episode}) async {
    await platform.view.params.shouldInterceptRequest!(
        controller,
        WebResourceRequest(
            url: WebUri(url ?? _iframe),
            headers: {
              'Referer': referer,
              'User-Agent': 'synthetic comparison UA'
            },
            method: 'GET',
            isForMainFrame: false));
  }

  void fail(
      {String url = LegacyPlayerCompat.endpoint,
      int status = 403,
      Map<String, String>? headers = const {'Origin': 'null'},
      String? method = 'POST',
      bool? mainFrame = false}) {
    platform.view.params.onReceivedHttpError!(
        controller,
        WebResourceRequest(
            url: WebUri(url),
            headers: headers,
            method: method,
            isForMainFrame: mainFrame),
        WebResourceResponse(statusCode: status));
  }

  Future<void> flush() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> dispose() async {
    await subscription.cancel();
    await parser.dispose();
  }
}

class _Transport implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Future<ResponseBody> Function(RequestOptions)? post;
  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    requests.add(o);
    if (o.method == 'GET') {
      return ResponseBody.fromString(
          'window.__HHJX_BOOTSTRAP__ = ${jsonEncode({
                'url': _encoded,
                't': 123,
                'key': 'ab' * 32,
                'act': 99
              })};',
          200);
    }
    if (post != null) return await post!(o);
    return ResponseBody.fromString(
        jsonEncode({'code': 200, 'url': _media}), 200);
  }

  @override
  void close({bool force = false}) {}
}

class _Platform extends InAppWebViewPlatform {
  late _Headless view;
  @override
  PlatformHeadlessInAppWebView createPlatformHeadlessInAppWebView(
          PlatformHeadlessInAppWebViewCreationParams params) =>
      view = _Headless(params);
}

class _Headless extends PlatformHeadlessInAppWebView {
  _Headless(super.params) : super.implementation();
  final controller = _Controller();
  @override
  Future<void> run() async {
    params.onWebViewCreated?.call(controller);
  }

  @override
  Future<void> dispose() async {}
}

class _Controller implements PlatformInAppWebViewController {
  final handlers = <String, JavaScriptHandlerCallback>{};
  final interception = <bool?>[];
  WebUri? url;
  void reply(String name, List<dynamic> args) => handlers[name]!(args);
  @override
  void addJavaScriptHandler(
      {required String handlerName,
      required JavaScriptHandlerCallback callback}) {
    handlers[handlerName] = callback;
  }

  @override
  Future<void> loadUrl(
      {required URLRequest urlRequest,
      Uri? iosAllowingReadAccessTo,
      WebUri? allowingReadAccessTo}) async {
    url = urlRequest.url;
  }

  @override
  Future<WebUri?> getUrl() async => url;
  @override
  Future<dynamic> evaluateJavascript(
          {required String source, ContentWorld? contentWorld}) async =>
      null;
  @override
  Future<void> addUserScripts({required List<UserScript> userScripts}) async {}
  @override
  Future<void> removeUserScriptsByGroupName(
      {required String groupName}) async {}
  @override
  Future<void> setSettings({required InAppWebViewSettings settings}) async {
    interception.add(settings.useShouldInterceptRequest);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}
