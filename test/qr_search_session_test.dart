import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/qr_search_session.dart';

void main() {
  late HttpClient client;
  late QrSearchSession session;
  late Uri uri;
  late List<String> received;
  setUp(() async {
    client = HttpClient();
    received = [];
    session = QrSearchSession(onQuery: received.add);
    uri = await session.start(address: InternetAddress.loopbackIPv4);
  });
  tearDown(() async {
    client.close(force: true);
    await session.close();
  });
  Future<int> post(String body, {String? origin}) async {
    final req = await client.postUrl(uri);
    if (origin != null) req.headers.set('origin', origin);
    req.write(body);
    final result = await req.close();
    await result.drain<void>();
    return result.statusCode;
  }

  test('HTML form and UTF8 submission delivered once', () async {
    final response = await (await client.getUrl(uri)).close();
    expect(response.headers.value('cache-control'), 'no-store');
    expect(response.headers.value('referrer-policy'), 'same-origin');
    expect(
        await utf8.decoder.bind(response).join(), contains('maxlength="120"'));
    expect(await post('q=${Uri.encodeComponent(' 葬送的芙莉莲 ')}'), 200);
    expect(received, ['葬送的芙莉莲']);
    expect(await post('q=duplicate'), 409);
    expect(received.length, 1);
  });
  test('reject empty oversized malformed control and cross origin', () async {
    for (final body in [
      'q=',
      'q=${'a' * 121}',
      'q=%00',
      'q=%ZZ',
      'q=${'a' * 2050}'
    ]) {
      expect(await post(body), 400);
    }
    expect(await post('q=hello', origin: 'http://elsewhere'), 403);
    expect(received, isEmpty);
  });
  test('random route token and wrong path', () async {
    final other = QrSearchSession(onQuery: (_) {});
    expect(other.token, isNot(session.token));
    expect(session.token.length, 48);
    final response =
        await (await client.getUrl(uri.replace(path: '/wrong'))).close();
    expect(response.statusCode, 404);
    await response.drain<void>();
  });
  test('concurrent submissions accept only one', () async {
    final results = await Future.wait([post('q=one'), post('q=two')]);
    expect(results, containsAll([200, 409]));
    expect(received.length, 1);
  });
  test('exit closes listener and cannot reopen session', () async {
    await session.close();
    await expectLater(client.getUrl(uri), throwsA(isA<SocketException>()));
    await expectLater(
        session.start(address: InternetAddress.loopbackIPv4), throwsStateError);
  });
  test('expiry closes listener', () async {
    final expired = Completer<void>();
    final short = QrSearchSession(
        onQuery: (_) {},
        lifetime: const Duration(milliseconds: 20),
        onClosed: expired.complete);
    final address = await short.start(address: InternetAddress.loopbackIPv4);
    await expired.future;
    await expectLater(client.getUrl(address), throwsA(isA<SocketException>()));
  });
  test('continuous slow upload has a total deadline', () async {
    final socket = await Socket.connect(uri.host, uri.port);
    socket.write(
        'POST ${uri.path} HTTP/1.1\r\nHost: ${uri.host}\r\nContent-Length: 1000\r\n\r\nq=');
    final response = utf8.decoder.bind(socket).join();
    final timer = Timer.periodic(
        const Duration(milliseconds: 100), (_) => socket.write('a'));
    final text = await response.timeout(const Duration(seconds: 8));
    timer.cancel();
    socket.destroy();
    expect(text, contains('400'));
    expect(received, isEmpty);
  });
  test('exit during unfinished upload is isolated', () async {
    final socket = await Socket.connect(uri.host, uri.port);
    socket.write(
        'POST ${uri.path} HTTP/1.1\r\nHost: ${uri.host}\r\nContent-Length: 1000\r\n\r\nq=');
    await socket.flush();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await session.close();
    socket.destroy();
    expect(received, isEmpty);
  });
}
