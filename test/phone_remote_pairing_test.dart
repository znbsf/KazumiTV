import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/phone_keyboard.dart';
import 'package:kazumi/services/phone_keyboard_session.dart';
import 'package:kazumi/services/storage/phone_remote_pairing.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late PhoneRemotePairingStore store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kazumi_pairing_');
    store = PhoneRemotePairingStore(directory: dir);
  });
  tearDown(() async => dir.delete(recursive: true));

  test('pairing persists exactly seven days, rejects rollback and revokes',
      () async {
    final now = DateTime.now();
    final pairing = PhoneRemotePairing(
        token: 'a' * 32,
        port: 18921,
        createdAt: now,
        expiresAt: now.add(const Duration(days: 7)));
    await store.write(pairing);
    final restart = PhoneRemotePairingStore(directory: dir);
    expect((await restart.read(now: now.add(const Duration(days: 6))))?.token,
        pairing.token);
    expect(await restart.read(now: now.add(const Duration(days: 7))), isNull);
    expect(await restart.read(now: now.subtract(const Duration(seconds: 1))),
        isNull);
    await restart.clear();
    expect(await store.read(), isNull);
    expect(await File('${dir.path}/phone-remote-pairing.json').readAsString(),
        isNot(contains(pairing.token)));
  });

  test('malformed, oversized, unknown and invalid pairings never restore',
      () async {
    final file = File('${dir.path}/phone-remote-pairing.json');
    for (final contents in [
      '{',
      'x' * 3000,
      '{"version":2}',
      '{"version":1,"token":3}'
    ]) {
      await file.writeAsString(contents);
      expect(await store.read(), isNull);
    }
    final now = DateTime.now();
    for (final token in ['x' * 32, 'a']) {
      expect(
          PhoneRemotePairing(
                  token: token,
                  port: 12345,
                  createdAt: now,
                  expiresAt: now.add(const Duration(days: 7)))
              .validAt(now),
          false);
    }
    expect(
        PhoneRemotePairing(
                token: 'a' * 32,
                port: 12345,
                createdAt: now,
                expiresAt: now.add(const Duration(days: 8)))
            .validAt(now),
        false);
  });

  test(
      'cold restart and background resume retain URL, reset consent, revoke permanently',
      () async {
    var keyboard = PhoneKeyboard(pairingStore: store);
    final address = InternetAddress.loopbackIPv4;
    try {
      await keyboard.start(address: address, remember: true);
      final original = keyboard.uri!;
      final firstSession = keyboard.session!.sessionId;
      final expiry = keyboard.pairingExpiresAt!;
      keyboard.setReadTextAllowed(true);
      keyboard.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(keyboard.uri, isNull);
      expect(keyboard.readTextAllowed, false);
      keyboard.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await keyboard.restore(address: address);
      expect(keyboard.uri, original);
      expect(keyboard.session!.sessionId, isNot(firstSession));
      expect(keyboard.readTextAllowed, false);
      expect(keyboard.pairingExpiresAt!.isAtSameMomentAs(expiry), true);
      await keyboard.session!.close();
      keyboard.dispose();
      keyboard =
          PhoneKeyboard(pairingStore: PhoneRemotePairingStore(directory: dir));
      await keyboard.restore(address: address);
      expect(keyboard.uri, original);
      expect(keyboard.pairingExpiresAt!.isAtSameMomentAs(expiry), true);
      await keyboard.disconnect();
      await keyboard.restore(address: address);
      expect(keyboard.uri, isNull);
      expect(await store.read(), isNull);
    } finally {
      await keyboard.disconnect();
      keyboard.dispose();
    }
  });

  test('cancel during queued start cannot resurrect a listener or pairing',
      () async {
    final keyboard = PhoneKeyboard(pairingStore: store);
    try {
      final start =
          keyboard.start(address: InternetAddress.loopbackIPv4, remember: true);
      final stop = keyboard.disconnect();
      await Future.wait([start, stop]);
      expect(keyboard.uri, isNull);
      expect(await store.read(), isNull);
    } finally {
      keyboard.dispose();
    }
  });

  test(
      'pause preserves pairing across restart and only explicit resume opens it',
      () async {
    var keyboard = PhoneKeyboard(pairingStore: store);
    final address = InternetAddress.loopbackIPv4;
    try {
      await keyboard.start(address: address, remember: true);
      final uri = keyboard.uri;
      final expiry = keyboard.pairingExpiresAt!;
      keyboard.setReadTextAllowed(true);
      await keyboard.pause();
      expect(keyboard.uri, isNull);
      expect(keyboard.isPaused, true);
      expect(keyboard.hasPairing, true);
      expect(keyboard.readTextAllowed, false);
      keyboard.didChangeAppLifecycleState(AppLifecycleState.paused);
      keyboard.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await keyboard.restore(address: address);
      expect(keyboard.uri, isNull);
      keyboard.dispose();
      keyboard = PhoneKeyboard(pairingStore: store);
      await keyboard.restore(address: address);
      expect(keyboard.isPaused, true);
      expect(keyboard.uri, isNull);
      await keyboard.restore(address: address, resume: true);
      expect(keyboard.uri, uri);
      expect(keyboard.isPaused, false);
      expect(keyboard.pairingExpiresAt!.isAtSameMomentAs(expiry), true);
      expect(keyboard.readTextAllowed, false);
      expect((await store.read())!.paused, false);
      await keyboard.disconnect();
      expect(await store.read(), isNull);
    } finally {
      await keyboard.disconnect();
      keyboard.dispose();
    }
  });

  test('occupied saved port does not silently change the paired address',
      () async {
    final blocker = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final now = DateTime.now();
    await store.write(PhoneRemotePairing(
        token: 'a' * 32,
        port: blocker.port,
        createdAt: now,
        expiresAt: now.add(const Duration(days: 7))));
    final keyboard = PhoneKeyboard(pairingStore: store);
    try {
      await keyboard.restore(address: InternetAddress.loopbackIPv4);
      expect(keyboard.uri, isNull);
      expect(keyboard.hasPairing, true);
      expect(keyboard.error, isNotNull);
      await blocker.close();
      await keyboard.restore(address: InternetAddress.loopbackIPv4);
      expect(keyboard.uri?.port, (await store.read())?.port);
    } finally {
      await blocker.close();
      await keyboard.disconnect();
      keyboard.dispose();
    }
  });

  test(
      'old session command rejected after reopening same URL; fresh request executes once',
      () async {
    var calls = 0;
    final expiry = DateTime.now().add(const Duration(days: 7));
    PhoneKeyboardSession create({String? token, int port = 0}) =>
        PhoneKeyboardSession(
            accessToken: token,
            port: port,
            expiresAt: expiry,
            remoteState: () => {
                  'revision': 1,
                  'keys': [
                    {'id': 'ok', 'label': 'OK'}
                  ]
                },
            dispatchRemote: (_, {required revision}) async {
              calls++;
              return true;
            });
    var session = create();
    final client =
        HttpOverrides.runWithHttpOverrides(() => HttpClient(), _RealHttp());
    try {
      final uri = await session.start(address: InternetAddress.loopbackIPv4);
      final oldId = session.sessionId;
      final token = session.token;
      await session.close();
      session = create(token: token, port: uri.port);
      expect(await session.start(address: InternetAddress.loopbackIPv4), uri);
      Future<int> send(String? epoch, String id) async {
        final request =
            await client.postUrl(uri.replace(path: '${uri.path}/input'));
        request.write(jsonEncode({
          'sessionId': epoch,
          'requestId': id,
          'action': 'remote',
          'key': 'ok',
          'remoteRevision': 1,
          'remoteSequence': 1
        }));
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      }

      expect(await send(oldId, 'old'), 409);
      expect(await send(null, 'missing'), 409);
      expect(calls, 0);
      expect(await send(session.sessionId, 'new'), 200);
      expect(await send(session.sessionId, 'new'), 200);
      expect(calls, 1);
    } finally {
      client.close(force: true);
      await session.close();
    }
  });

  test(
      'paired listener ignores temporary idle timeout but closes at absolute expiry',
      () async {
    final session = PhoneKeyboardSession(
        idleTimeout: const Duration(milliseconds: 1),
        expiresAt: DateTime.now().add(const Duration(milliseconds: 350)));
    final client =
        HttpOverrides.runWithHttpOverrides(() => HttpClient(), _RealHttp());
    try {
      final uri = await session.start(address: InternetAddress.loopbackIPv4);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(session.isClosed, false);
      final response =
          await (await client.getUrl(uri.replace(path: '${uri.path}/state')))
              .close();
      await response.drain<void>();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(session.isClosed, true);
    } finally {
      client.close(force: true);
      await session.close();
    }
  });
}
