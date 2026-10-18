import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/phone_keyboard_session.dart';

void main() {
  late HttpClient client;
  late PhoneKeyboardSession session;
  late Uri uri;
  late List<String> edits;
  late int confirms;
  PhoneKeyboardTarget target(String label, {int maxLength = 2048}) =>
      PhoneKeyboardTarget(
        label: label,
        maxLength: maxLength,
        onText: (text) => edits.add('$label:$text'),
        onConfirm: () => confirms++,
      );
  setUp(() async {
    client = HttpClient();
    edits = [];
    confirms = 0;
    session = PhoneKeyboardSession();
    uri = await session.start(address: InternetAddress.loopbackIPv4);
  });
  tearDown(() async {
    client.close(force: true);
    await session.close();
  });
  Map<String, Object?> payload(
    String id, {
    String action = 'input',
    String text = 'hello',
  }) {
    final state = session.state;
    final t = state['target'] as Map<String, Object?>?;
    return {
      'requestId': id,
      'targetId': t?['id'],
      'generation': state['generation'],
      'revision': t?['revision'],
      'action': action,
      'text': text,
    };
  }

  Future<int> post(Object data, {String? origin}) async {
    final req = await client.postUrl(uri.replace(path: '${uri.path}/input'));
    if (origin != null) req.headers.set('origin', origin);
    req.headers.contentType = ContentType.json;
    req.add(utf8.encode(jsonEncode(data)));
    final result = await req.close();
    await result.drain<void>();
    return result.statusCode;
  }

  test(
      'multiple edits clear and confirm across fields do not expose field contents',
      () async {
    session.setTarget(target('search'));
    expect(await post(payload('1', text: '秘密')), 200);
    expect(await post(payload('2', text: 'second')), 200);
    expect(await post(payload('3', action: 'clear')), 200);
    expect(await post(payload('4', action: 'confirm')), 200);
    session.setTarget(target('rule URL'));
    expect(await post(payload('5', text: 'https://local/?token=secret')), 200);
    final response = await (await client.getUrl(
      uri.replace(path: '${uri.path}/state'),
    ))
        .close();
    final body = await utf8.decoder.bind(response).join();
    expect(body, isNot(contains('secret')));
    expect(body, isNot(contains('second')));
    expect(edits, [
      'search:秘密',
      'search:second',
      'search:',
      'rule URL:https://local/?token=secret',
    ]);
    expect(confirms, 1);
  });
  test(
    'identical receipt replay has no effects and altered replay conflicts',
    () async {
      session.setTarget(target('a'));
      final first = payload('same');
      expect(await post(first), 200);
      expect(await post(first), 200);
      expect(await post({...first, 'text': 'changed'}), 409);
      expect(await post({...first, 'requestId': 'old-revision'}), 409);
      expect(edits, ['a:hello']);
    },
  );
  test('old field generation and detached target reject input', () async {
    final a = target('a');
    session.setTarget(a);
    final old = payload('old');
    session.setTarget(target('b'));
    expect(await post(old), 409);
    session.setTarget(a);
    expect(await post(old), 409);
    session.setTarget(null);
    expect(await post(payload('none')), 409);
    expect(edits, isEmpty);
  });
  test('target switch while upload is incomplete rejects delayed body',
      () async {
    session.setTarget(target('a'));
    final bytes = utf8.encode(jsonEncode(payload('delayed')));
    final socket = await Socket.connect(uri.host, uri.port);
    socket.write(
      'POST ${uri.path}/input HTTP/1.1\r\nHost: ${uri.host}\r\nContent-Length: ${bytes.length}\r\nConnection: close\r\n\r\n',
    );
    socket.add(bytes.sublist(0, 2));
    await socket.flush();
    final response = utf8.decoder.bind(socket).join();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    session.setTarget(target('b'));
    socket.add(bytes.sublist(2));
    await socket.flush();
    expect(await response.timeout(const Duration(seconds: 3)), contains('409'));
    socket.destroy();
    expect(edits, isEmpty);
  });
  test(
    'invalid origin types actions controls and length have no effects',
    () async {
      session.setTarget(target('a', maxLength: 3));
      expect(await post(payload('origin'), origin: 'http://elsewhere'), 403);
      for (final data in [
        [],
        {'requestId': ''},
        payload('long', text: 'abcd'),
        payload('control', text: '\u0000'),
        payload('action', action: 'install'),
        {...payload('type'), 'text': 1},
      ]) {
        expect(await post(data), 400);
      }
      expect(edits, isEmpty);
      expect(confirms, 0);
      expect(await post(payload('unicode', text: '😀😀😀')), 200);
    },
  );
  test('inactive editor hides target and rejects late requests', () async {
    var active = true;
    session.setTarget(PhoneKeyboardTarget(
        label: 'a',
        isActive: () => active,
        onText: edits.add,
        onConfirm: () => confirms++));
    final old = payload('inactive');
    active = false;
    expect(session.state['target'], isNull);
    expect(await post(old), 409);
    expect(edits, isEmpty);
  });
  test('evicted receipts still cannot replay an old revision', () async {
    session.setTarget(target('a'));
    final first = payload('first');
    expect(await post(first), 200);
    for (var i = 0; i < 129; i++) {
      expect(await post(payload('next-$i')), 200);
    }
    expect(await post(first), 409);
    expect(edits.length, 130);
  });
  test('disconnect during unfinished upload does not mutate target', () async {
    session.setTarget(target('a'));
    final socket = await Socket.connect(uri.host, uri.port);
    socket.write(
        'POST ${uri.path}/input HTTP/1.1\r\nHost: ${uri.host}\r\nContent-Length: 1000\r\n\r\n{');
    await socket.flush();
    socket.destroy();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(edits, isEmpty);
    expect(await post(payload('after-disconnect')), 200);
  });
  test('slow continuous upload has an absolute deadline', () async {
    session.setTarget(target('a'));
    final socket = await Socket.connect(uri.host, uri.port);
    socket.write(
        'POST ${uri.path}/input HTTP/1.1\r\nHost: ${uri.host}\r\nContent-Length: 10000\r\nConnection: close\r\n\r\n{');
    final response = utf8.decoder.bind(socket).join();
    final timer = Timer.periodic(
        const Duration(milliseconds: 100), (_) => socket.write(' '));
    try {
      expect(
          await response.timeout(const Duration(seconds: 8)), contains('400'));
      expect(edits, isEmpty);
    } finally {
      timer.cancel();
      socket.destroy();
    }
  });
  test('concurrent same revision accepts one mutation', () async {
    session.setTarget(target('a'));
    final a = payload('a'), b = payload('b');
    expect(await Future.wait([post(a), post(b)]), containsAll([200, 409]));
    expect(edits.length, 1);
  });
  test(
    'polling does not extend idle expiration and closed session cannot reopen',
    () async {
      await session.close();
      final closed = Completer<void>();
      session = PhoneKeyboardSession(
        idleTimeout: const Duration(milliseconds: 250),
        onClosed: closed.complete,
      );
      uri = await session.start(address: InternetAddress.loopbackIPv4);
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        final response = await (await client.getUrl(
          uri.replace(path: '${uri.path}/state'),
        ))
            .close();
        await response.drain<void>();
      }
      await closed.future.timeout(const Duration(seconds: 2));
      expect(session.isClosed, isTrue);
      await expectLater(
        session.start(address: InternetAddress.loopbackIPv4),
        throwsStateError,
      );
      await expectLater(client.getUrl(uri), throwsA(isA<SocketException>()));
    },
  );
}
