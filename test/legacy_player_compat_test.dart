import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/video_source/legacy_player_compat.dart';

const episode = 'https://dmbus.cc/p/6330-1-2.html';
final encrypted = 'ab' * 32;
final player = '${LegacyPlayerCompat.origin}/?url=$encrypted';
const media = 'https://video.example/test.mp4?token=fixture';
String bootstrap({String? url}) => 'window.__HHJX_BOOTSTRAP__ = '
    '${jsonEncode({
          'url': url ?? encrypted,
          't': 123,
          'key': 'cd' * 32,
          'act': 99
        })};';

class Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Future<ResponseBody> Function(RequestOptions)? handle;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (handle != null) return handle!(options);
    return ResponseBody.fromString(
        options.method == 'GET'
            ? bootstrap()
            : jsonEncode({'code': 200, 'url': media}),
        200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Adapter adapter;
  late LegacyPlayerCompat compat;
  void observe([String? url, String referrer = episode]) => compat.observePage(
      url ?? player, {'Referer': referrer, 'User-Agent': 'fixture UA'});
  Future<String?> fail() => compat.onHttpError(LegacyPlayerCompat.endpoint, 403,
      requestHeaders: const {'Origin': 'null'},
      method: 'POST',
      isForMainFrame: false);
  setUp(() {
    adapter = Adapter();
    compat = LegacyPlayerCompat(client: Dio()..httpClientAdapter = adapter);
    compat.begin(episode, enabled: true);
    observe();
  });
  tearDown(() => compat.cancel());

  test('bare 403 is insufficient without observed null-Origin request context',
      () async {
    expect(await compat.onHttpError(LegacyPlayerCompat.endpoint, 403), isNull);
    expect(adapter.requests, isEmpty);
  });

  test('fresh same-origin bootstrap yields media once, without player scripts',
      () async {
    expect(await fail(), media);
    expect(adapter.requests.map((r) => r.method), ['GET', 'POST']);
    final post = adapter.requests.last;
    expect(post.uri.toString(), LegacyPlayerCompat.endpoint);
    expect(post.followRedirects, isFalse);
    expect(post.headers['Origin'], LegacyPlayerCompat.origin);
    expect(post.headers['Referer'], player);
    expect(post.headers['User-Agent'], 'fixture UA');
    expect(post.data['client_fallback'], isFalse);
    expect(post.data['url'], encrypted);
    expect(await fail(), isNull);
    expect(adapter.requests, hasLength(2));
  });
  test('disabled, unrelated and ambiguous episodes produce no requests',
      () async {
    for (final input in [
      'https://other.example/p/6330-1-2.html',
      '$episode?x=1',
      '$episode#x',
      'http://dmbus.cc/p/6330-1-2.html'
    ]) {
      compat.begin(input, enabled: true);
      observe(player, input);
      expect(await fail(), isNull);
    }
    compat.begin(episode, enabled: false);
    observe();
    expect(await fail(), isNull);
    compat.begin(episode, enabled: true);
    observe();
    observe('${LegacyPlayerCompat.origin}/?url=${'ef' * 32}');
    expect(await fail(), isNull);
    expect(adapter.requests, isEmpty);
  });
  test('only exact iframe and current episode referrer are admitted', () async {
    for (final url in [
      '/relative',
      'data:text/plain,x',
      'https://evil.example/?url=$encrypted',
      '${LegacyPlayerCompat.origin}/?url=$encrypted&extra=1',
      '${LegacyPlayerCompat.origin}/?url=$encrypted&url=$encrypted',
      '${LegacyPlayerCompat.origin}/?url=invalid',
      'https://user@hhjx.hhplayer.com/?url=$encrypted'
    ]) {
      compat.begin(episode, enabled: true);
      observe(url);
      expect(await fail(), isNull);
    }
    compat.begin(episode, enabled: true);
    observe(player, 'https://dmbus.cc/p/6330-1-3.html');
    compat.observePage(player, null);
    expect(await fail(), isNull);
    expect(adapter.requests, isEmpty);
  });
  test('no retry for success, unrelated error, or non-exact API', () async {
    expect(await compat.onHttpError(LegacyPlayerCompat.endpoint, 200), isNull);
    expect(await compat.onHttpError(LegacyPlayerCompat.endpoint, 500), isNull);
    expect(await compat.onHttpError('${LegacyPlayerCompat.endpoint}?x=1', 403),
        isNull);
    expect(adapter.requests, isEmpty);
  });
  test('invalid or mismatched fresh bootstrap never reaches API', () async {
    for (final body in [
      'not bootstrap',
      bootstrap(url: 'ef' * 32),
      'window.__HHJX_BOOTSTRAP__ = {bad};',
      'x' * 65537
    ]) {
      compat.begin(episode, enabled: true);
      observe();
      adapter.requests.clear();
      adapter.handle = (_) async => ResponseBody.fromString(body, 200);
      expect(await fail(), isNull);
      expect(adapter.requests, hasLength(1));
    }
  });
  test('redirects, invalid response and non-media URLs fail closed', () async {
    for (final body in [
      jsonEncode({'code': 403, 'url': media}),
      jsonEncode({'code': 200, 'url': media, 'ext': 'unsupported'}),
      jsonEncode({'code': 200, 'url': 'https://video.example/player.html'}),
      jsonEncode({'code': 200, 'url': 'http://video.example/test.mp4'}),
      'not json',
      'x' * 16385
    ]) {
      compat.begin(episode, enabled: true);
      observe();
      adapter.handle = (r) async =>
          ResponseBody.fromString(r.method == 'GET' ? bootstrap() : body, 200);
      expect(await fail(), isNull);
    }
    compat.begin(episode, enabled: true);
    observe();
    adapter.handle = (_) async => ResponseBody.fromString('', 302, headers: {
          'location': ['https://elsewhere.example/']
        });
    expect(await fail(), isNull);
  });
  test('cancellation and episode change discard late API response', () async {
    final pending = Completer<ResponseBody>();
    final entered = Completer<void>();
    adapter.handle = (r) async {
      if (r.method == 'GET') return ResponseBody.fromString(bootstrap(), 200);
      entered.complete();
      return pending.future;
    };
    final result = fail();
    await entered.future;
    compat.begin('https://dmbus.cc/p/6330-1-3.html', enabled: true);
    pending.complete(
        ResponseBody.fromString(jsonEncode({'code': 200, 'url': media}), 200));
    expect(await result, isNull);
    observe(player, episode);
    expect(await fail(), isNull);
  });
  test('deadline cancels a pending transport request', () async {
    compat.cancel();
    compat = LegacyPlayerCompat(
        client: Dio()..httpClientAdapter = adapter,
        budget: const Duration(milliseconds: 20));
    compat.begin(episode, enabled: true);
    observe();
    final pending = Completer<ResponseBody>();
    adapter.handle = (_) => pending.future;
    expect(await fail().timeout(const Duration(seconds: 1)), isNull);
    expect(adapter.requests.single.cancelToken?.isCancelled, isTrue);
    pending.complete(ResponseBody.fromString(bootstrap(), 200));
  });

  test('deadline also cancels a stalled response body', () async {
    compat.cancel();
    compat = LegacyPlayerCompat(
        client: Dio()..httpClientAdapter = adapter,
        budget: const Duration(milliseconds: 20));
    compat.begin(episode, enabled: true);
    observe();
    final body = StreamController<Uint8List>();
    adapter.handle = (_) async => ResponseBody(body.stream, 200);
    expect(await fail().timeout(const Duration(seconds: 1)), isNull);
    expect(adapter.requests.single.cancelToken?.isCancelled, isTrue);
    await body.close();
  });

  test('ambiguity arriving during parsing cancels the attempt', () async {
    final pending = Completer<ResponseBody>();
    final entered = Completer<void>();
    adapter.handle = (_) {
      entered.complete();
      return pending.future;
    };
    final result = fail();
    await entered.future;
    observe('${LegacyPlayerCompat.origin}/?url=${'ef' * 32}');
    expect(await result.timeout(const Duration(seconds: 1)), isNull);
    pending.complete(ResponseBody.fromString(bootstrap(), 200));
    expect(await fail(), isNull);
    expect(adapter.requests, hasLength(1));
  });
}
