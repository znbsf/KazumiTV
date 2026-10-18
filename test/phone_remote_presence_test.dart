import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/phone_keyboard_session.dart';

void main() {
  test(
      'heartbeats deduplicate browsers, expire independently and notify offline',
      () async {
    var changes = 0;
    final session = PhoneKeyboardSession(
        presenceTimeout: const Duration(milliseconds: 300),
        onPresenceChanged: () => changes++);
    final client = HttpClient();
    final uri = await session.start(address: InternetAddress.loopbackIPv4);
    Future<int> poll(String id, {String? origin}) async {
      final request =
          await client.getUrl(uri.replace(path: '${uri.path}/state'));
      request.headers.set('X-Kazumi-Client', id);
      if (origin != null) request.headers.set('Origin', origin);
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    }

    try {
      expect(session.onlineCount, 0);
      await poll('invalid');
      expect(session.onlineCount, 0);
      expect(await poll('a' * 24, origin: 'http://invalid'), 403);
      expect(session.onlineCount, 0);
      await poll('a' * 24);
      await poll('a' * 24);
      expect(session.onlineCount, 1);
      expect(changes, 1);
      await poll('b' * 24);
      expect(session.onlineCount, 2);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await poll('b' * 24);
      await Future<void>.delayed(const Duration(milliseconds: 180));
      expect(session.onlineCount, 1);
      expect(changes, 3);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(session.onlineCount, 0);
      expect(session.clientConnected, false);
      expect(changes, 4);
      await poll('a' * 24);
      expect(session.onlineCount, 1);
      await session.close();
      expect(session.onlineCount, 0);
      expect(session.clientConnected, false);
    } finally {
      client.close(force: true);
      await session.close();
    }
  });

  test(
      'successful input keeps its browser online; polling never extends idle expiry',
      () async {
    final session = PhoneKeyboardSession(
        idleTimeout: const Duration(milliseconds: 450),
        presenceTimeout: const Duration(milliseconds: 150));
    final target =
        PhoneKeyboardTarget(label: 'test', onText: (_) {}, onConfirm: () {});
    session.setTarget(target);
    final client = HttpClient();
    final uri = await session.start(address: InternetAddress.loopbackIPv4);
    try {
      final request =
          await client.postUrl(uri.replace(path: '${uri.path}/input'));
      request.headers.set('X-Kazumi-Client', 'a' * 24);
      request.write(jsonEncode({
        'requestId': 'input',
        'targetId': target.id,
        'generation': session.state['generation'],
        'revision': 0,
        'action': 'input',
        'text': 'hello'
      }));
      final response = await request.close();
      await response.drain<void>();
      expect(response.statusCode, 200);
      expect(session.onlineCount, 1);
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final heartbeat =
            await client.getUrl(uri.replace(path: '${uri.path}/state'));
        heartbeat.headers.set('X-Kazumi-Client', 'a' * 24);
        await (await heartbeat.close()).drain<void>();
        expect(session.onlineCount, 1);
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(session.isClosed, true);
      expect(session.onlineCount, 0);
    } finally {
      client.close(force: true);
      await session.close();
    }
  });
}
