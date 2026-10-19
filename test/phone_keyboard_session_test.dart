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
  test('only a valid state handshake connects once; page fetch does not',
      () async {
    var connected = 0;
    final local = PhoneKeyboardSession(onConnected: () => connected++);
    final endpoint = await local.start(address: InternetAddress.loopbackIPv4);
    final http = HttpClient();
    try {
      for (final path in [endpoint.path, '/invalid/state']) {
        final response =
            await (await http.getUrl(endpoint.replace(path: path))).close();
        await response.drain<void>();
        expect(connected, 0);
      }
      for (var i = 0; i < 2; i++) {
        final response = await (await http
                .getUrl(endpoint.replace(path: '${endpoint.path}/state')))
            .close();
        await response.drain<void>();
      }
      expect(connected, 1);
      expect(local.clientConnected, isTrue);
      expect(local.isClosed, isFalse);
    } finally {
      http.close(force: true);
      await local.close();
    }
  });
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
    'read permission defaults off and revocation isolates old generation',
    () async {
      session.setTarget(
        PhoneKeyboardTarget(
          label: 'ordinary',
          onText: edits.add,
          onConfirm: () {},
          readValue: () => {
            'text': 'private draft',
            'selection': {'baseOffset': 0, 'extentOffset': 7},
          },
        ),
      );
      expect(session.state['readTextAllowed'], false);
      expect(jsonEncode(session.state), isNot(contains('private draft')));
      session.setReadTextAllowed(true);
      expect(session.state['readTextAllowed'], true);
      expect((session.state['target'] as Map)['text'], 'private draft');
      final authorized = payload('before-revoke');
      session.setReadTextAllowed(false);
      expect(jsonEncode(session.state), isNot(contains('private draft')));
      expect(await post(authorized), 409);
      expect(edits, isEmpty);
      await session.close();
      expect(session.state['target'], isNull);
      expect(session.state['readTextAllowed'], false);
    },
  );

  test(
    'write-only credentials never read values even with global permission',
    () async {
      var reads = 0;
      session.setTarget(PhoneKeyboardTarget(
        label: 'Access Token',
        writeOnly: true,
        onText: edits.add,
        onConfirm: () => confirms++,
        readValue: () {
          reads++;
          return {
            'text': 'saved-secret-token',
            'selection': {'baseOffset': 0, 'extentOffset': 18},
          };
        },
        onSelection: (_, __) => fail('Credentials cannot expose selection'),
      ));
      session.setReadTextAllowed(true);
      expect(session.state['readTextAllowed'], false);
      expect((session.state['target'] as Map)['writeOnly'], true);
      expect(jsonEncode(session.state), isNot(contains('saved-secret-token')));
      final response =
          await (await client.getUrl(uri.replace(path: '${uri.path}/state')))
              .close();
      final stateBody = await utf8.decoder.bind(response).join();
      expect(stateBody, isNot(contains('saved-secret-token')));
      expect(stateBody, isNot(contains('baseOffset')));
      expect(
          await post({
            ...payload('credential-selection', action: 'selection'),
            'selection': {'baseOffset': 0, 'extentOffset': 0},
          }),
          400);
      expect(
          await post({
            ...payload('credential-with-selection', text: 'new-token'),
            'selection': {'baseOffset': 0, 'extentOffset': 0},
          }),
          400);
      expect(edits, isEmpty);
      expect(reads, 0);
      expect(await post(payload('credential-replace', text: 'new-token')), 200);
      expect(edits, ['new-token']);
      expect(await post(payload('credential-confirm', action: 'confirm')), 200);
      expect(confirms, 1);
      expect(reads, 0);
      session.setTarget(PhoneKeyboardTarget(
        label: 'ordinary',
        onText: (_) {},
        onConfirm: () {},
        readValue: () => {'text': 'ordinary text'},
      ));
      expect(session.state['readTextAllowed'], true);
      expect((session.state['target'] as Map)['text'], 'ordinary text');
    },
  );

  test(
    'selection requires permission and validates offsets without text mutation',
    () async {
      final selected = <List<int>>[];
      session.setTarget(
        PhoneKeyboardTarget(
          label: 'ordinary',
          onText: edits.add,
          onConfirm: () {},
          readValue: () => {
            'text': 'abcd',
            'selection': {'baseOffset': 0, 'extentOffset': 0},
          },
          onSelection: (a, b) => selected.add([a, b]),
        ),
      );
      Map<String, Object?> selection(String id, Object a, Object b) => {
            ...payload(id, action: 'selection'),
            'selection': {'baseOffset': a, 'extentOffset': b},
          };
      expect(await post(selection('unauthorized', 0, 2)), isNot(200));
      session.setReadTextAllowed(true);
      for (final pair in [
        [-1, 2],
        [0, 5],
        ['0', 2],
        [0.5, 2],
      ]) {
        expect(await post(selection('bad-$pair', pair[0], pair[1])), 400);
      }
      expect(selected, isEmpty);
      expect(await post(selection('valid', 3, 1)), 200);
      expect(selected, [
        [3, 1],
      ]);
      expect(edits, isEmpty);
    },
  );

  test(
    'authorized reading hides inactive target and reopening starts untrusted',
    () async {
      var active = true;
      session.setTarget(
        PhoneKeyboardTarget(
          label: 'ordinary',
          onText: edits.add,
          onConfirm: () {},
          isActive: () => active,
          readValue: () => {
            'text': 'secret',
            'selection': {'baseOffset': 0, 'extentOffset': 0},
          },
        ),
      );
      session.setReadTextAllowed(true);
      expect((session.state['target'] as Map)['text'], 'secret');
      active = false;
      expect(session.state['target'], isNull);
      expect(jsonEncode(session.state), isNot(contains('secret')));
      await session.close();
      session = PhoneKeyboardSession();
      uri = await session.start(address: InternetAddress.loopbackIPv4);
      session.setTarget(PhoneKeyboardTarget(
          label: 'new ordinary',
          onText: edits.add,
          onConfirm: () {},
          readValue: () => {
                'text': 'new private text',
                'selection': {'baseOffset': 0, 'extentOffset': 1}
              }));
      expect(session.state['readTextAllowed'], false);
      expect((session.state['target'] as Map).containsKey('text'), isFalse);
      expect(
          (session.state['target'] as Map).containsKey('selection'), isFalse);
    },
  );

  test('cross-field stale confirm and selection cannot affect either field',
      () async {
    var selected = 0;
    final a = PhoneKeyboardTarget(
        label: 'a',
        onText: edits.add,
        onConfirm: () => confirms++,
        readValue: () => {'text': 'abc'},
        onSelection: (_, __) => selected++);
    session.setTarget(a);
    session.setReadTextAllowed(true);
    final oldConfirm = payload('old-confirm', action: 'confirm');
    final oldSelection = {
      ...payload('old-selection', action: 'selection'),
      'selection': {'baseOffset': 0, 'extentOffset': 2}
    };
    session.setTarget(target('b'));
    expect(await post(oldConfirm), 409);
    expect(await post(oldSelection), 409);
    session.setTarget(a);
    expect(await post(oldConfirm), 409);
    expect(await post(oldSelection), 409);
    expect(confirms, 0);
    expect(selected, 0);
    expect(edits, isEmpty);
  });

  test('explicit disconnect rejects old token on a newly started listener',
      () async {
    session.setTarget(target('old'));
    final oldToken = session.token;
    final oldBody = payload('old-request');
    await session.close();
    var remoteCalls = 0;
    session = PhoneKeyboardSession(
        remoteState: () => {
              'context': 'new',
              'revision': 1,
              'keys': [
                {'id': 'down', 'label': 'down'}
              ],
            },
        dispatchRemote: (_, {required revision}) async {
          remoteCalls++;
          return true;
        });
    uri = await session.start(address: InternetAddress.loopbackIPv4);
    session.setTarget(target('new'));
    expect(session.token, isNot(oldToken));
    final request = await client.postUrl(uri.replace(path: '/$oldToken/input'));
    request.add(utf8.encode(jsonEncode(oldBody)));
    final response = await request.close();
    expect(response.statusCode, 404);
    await response.drain<void>();
    final remote = await client.postUrl(uri.replace(path: '/$oldToken/input'));
    remote.add(utf8.encode(jsonEncode({
      'requestId': 'old-remote',
      'action': 'remote',
      'key': 'down',
      'remoteRevision': 1,
      'remoteSequence': 1
    })));
    final remoteResponse = await remote.close();
    expect(remoteResponse.statusCode, 404);
    await remoteResponse.drain<void>();
    expect(remoteCalls, 0);
    expect(await post(oldBody), 409);
    expect(edits, isEmpty);
  });

  test(
    'remote keys validate revision and receipts never execute twice',
    () async {
      await session.close();
      final calls = <String>[];
      session = PhoneKeyboardSession(
        remoteState: () => {
          'revision': 7,
          'context': 'qa',
          'keys': [
            {'id': 'up', 'label': 'up'},
            {'id': 'down', 'label': 'down'},
          ],
        },
        dispatchRemote: (key, {required revision}) async {
          calls.add('$key:$revision');
          return true;
        },
      );
      uri = await session.start(address: InternetAddress.loopbackIPv4);
      Map<String, Object?> remote(String id, String key, int revision) => {
            'requestId': id,
            'action': 'remote',
            'key': key,
            'remoteRevision': revision,
            'remoteSequence': (session.state['remoteSequence'] as int) + 1,
          };
      expect(await post(remote('bad-key', 'install', 7)), 409);
      expect(await post(remote('old', 'down', 6)), 409);
      final valid = remote('valid', 'down', 7);
      expect(await post(valid), 200);
      expect(await post(valid), 200);
      expect(await post(remote('valid', 'up', 7)), 409);
      expect(await post(remote('too-fast', 'up', 7)), 429);
      expect(calls, ['down:7']);
      await Future<void>.delayed(const Duration(milliseconds: 140));
      expect(await post(remote('next', 'up', 7)), 200);
      expect(calls, ['down:7', 'up:7']);
      final beforeControlDialog = remote('late-control', 'up', 7);
      session.invalidateRemoteRequests();
      session.invalidateRemoteRequests();
      await Future<void>.delayed(const Duration(milliseconds: 140));
      expect(await post(beforeControlDialog), 409);
      expect(calls.length, 2);
    },
  );

  test(
    'inflight remote command is serial and rejects parallel new command',
    () async {
      await session.close();
      final entered = Completer<void>();
      final finish = Completer<bool>();
      var calls = 0;
      session = PhoneKeyboardSession(
        remoteState: () => {
          'revision': 1,
          'context': 'qa',
          'keys': [
            {'id': 'up', 'label': 'up'},
            {'id': 'down', 'label': 'down'},
          ],
        },
        dispatchRemote: (key, {required revision}) {
          calls++;
          if (!entered.isCompleted) entered.complete();
          return finish.future;
        },
      );
      uri = await session.start(address: InternetAddress.loopbackIPv4);
      final first = {
        'requestId': 'one',
        'action': 'remote',
        'key': 'down',
        'remoteRevision': 1,
        'remoteSequence': 1,
      };
      final pending = post(first);
      await entered.future.timeout(const Duration(seconds: 2));
      expect(
          await post({...first, 'requestId': 'two', 'remoteSequence': 2}), 429);
      final duplicate = post(first);
      expect(calls, 1);
      finish.complete(true);
      expect(await pending, 200);
      expect(await duplicate, 200);
      expect(await post(first), 200);
      expect(calls, 1);
    },
  );

  test('timed out dispatch stays locked and replay never dispatches again',
      () async {
    await session.close();
    final finish = Completer<bool>();
    var calls = 0;
    session = PhoneKeyboardSession(
        remoteState: () => {
              'context': 'qa',
              'revision': 1,
              'keys': [
                {'id': 'down', 'label': 'down'}
              ]
            },
        dispatchRemote: (key, {required revision}) {
          calls++;
          return finish.future;
        });
    uri = await session.start(address: InternetAddress.loopbackIPv4);
    final data = {
      'requestId': 'timeout',
      'action': 'remote',
      'key': 'down',
      'remoteRevision': 1,
      'remoteSequence': 1,
    };
    expect(await post(data), 504);
    expect(await post(data), 504);
    expect(
        await post({...data, 'requestId': 'while-busy', 'remoteSequence': 2}),
        429);
    expect(calls, 1);
    finish.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(await post(data), 504);
    expect(calls, 1);
  });

  test('clear and confirm reject selection before any callback', () async {
    var textCalls = 0;
    var selectionCalls = 0;
    var confirmCalls = 0;
    final active = PhoneKeyboardTarget(
      label: 'ordinary',
      onText: (_) => textCalls++,
      onConfirm: () => confirmCalls++,
      readValue: () => {'text': 'original'},
      onSelection: (_, __) => selectionCalls++,
    );
    session.setTarget(active);
    session.setReadTextAllowed(true);
    final revision = active.revision;
    for (final action in ['clear', 'confirm']) {
      for (final selection in [
        null,
        {'baseOffset': 0, 'extentOffset': 1}
      ]) {
        expect(
            await post({
              ...payload('$action-${selection == null}', action: action),
              'selection': selection,
            }),
            400);
      }
    }
    expect(textCalls, 0);
    expect(confirmCalls, 0);
    expect(selectionCalls, 0);
    expect(active.revision, revision);
  });

  test('input with selection is atomic and requires read authorization',
      () async {
    var current = 'old';
    final selected = <List<int>>[];
    session.setTarget(PhoneKeyboardTarget(
        label: 'ordinary',
        onText: (text) {
          current = text;
          edits.add(text);
        },
        onConfirm: () {},
        readValue: () => {'text': current},
        onSelection: (a, b) => selected.add([a, b])));
    Map<String, Object?> input(String id, int end) => {
          ...payload(id, text: 'abcdef'),
          'selection': {'baseOffset': 1, 'extentOffset': end}
        };
    expect(await post(input('denied', 6)), 400);
    expect(current, 'old');
    session.setReadTextAllowed(true);
    expect(await post(input('bad', 7)), 400);
    expect(edits, isEmpty);
    expect(await post(input('valid', 6)), 200);
    expect(current, 'abcdef');
    expect(selected, [
      [1, 6]
    ]);
  });

  test('remote sequence rejects replay after bounded receipts are evicted',
      () async {
    await session.close();
    var calls = 0;
    session = PhoneKeyboardSession(
        remoteState: () => {
              'context': 'same',
              'revision': 1,
              'keys': [
                {'id': 'down', 'label': 'down'}
              ],
            },
        dispatchRemote: (_, {required revision}) async {
          calls++;
          return true;
        });
    uri = await session.start(address: InternetAddress.loopbackIPv4);
    final old = {
      'requestId': 'old-remote',
      'action': 'remote',
      'key': 'down',
      'remoteRevision': 1,
      'remoteSequence': 1
    };
    expect(await post(old), 200);
    session.setTarget(target('fill receipts'));
    for (var i = 0; i < 128; i++) {
      expect(await post(payload('fill-$i')), 200);
    }
    await Future<void>.delayed(const Duration(milliseconds: 140));
    expect(await post(old), 409);
    expect(calls, 1);
  });

  test('delayed remote body rechecks current remote revision', () async {
    await session.close();
    var revision = 1;
    var calls = 0;
    session = PhoneKeyboardSession(
      remoteState: () => {
        'revision': revision,
        'context': 'qa',
        'keys': [
          {'id': 'up', 'label': 'up'},
          {'id': 'down', 'label': 'down'},
        ],
      },
      dispatchRemote: (key, {required revision}) async {
        calls++;
        return true;
      },
    );
    uri = await session.start(address: InternetAddress.loopbackIPv4);
    final bytes = utf8.encode(
      jsonEncode({
        'requestId': 'delayed-remote',
        'action': 'remote',
        'key': 'down',
        'remoteRevision': 1,
        'remoteSequence': 1,
      }),
    );
    final socket = await Socket.connect(uri.host, uri.port);
    socket.write(
      'POST ${uri.path}/input HTTP/1.1\r\nHost: ${uri.host}\r\nContent-Length: ${bytes.length}\r\nConnection: close\r\n\r\n',
    );
    socket.add(bytes.sublist(0, 2));
    await socket.flush();
    final response = utf8.decoder.bind(socket).join();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    revision = 2;
    socket.add(bytes.sublist(2));
    await socket.flush();
    expect(await response.timeout(const Duration(seconds: 3)), contains('409'));
    socket.destroy();
    expect(calls, 0);
  });

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
    session.setTarget(
      PhoneKeyboardTarget(
        label: 'a',
        isActive: () => active,
        onText: edits.add,
        onConfirm: () => confirms++,
      ),
    );
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
      'POST ${uri.path}/input HTTP/1.1\r\nHost: ${uri.host}\r\nContent-Length: 1000\r\n\r\n{',
    );
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
      'POST ${uri.path}/input HTTP/1.1\r\nHost: ${uri.host}\r\nContent-Length: 10000\r\nConnection: close\r\n\r\n{',
    );
    final response = utf8.decoder.bind(socket).join();
    final timer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => socket.write(' '),
    );
    try {
      expect(
        await response.timeout(const Duration(seconds: 8)),
        contains('400'),
      );
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
