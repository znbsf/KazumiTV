import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/logging/log_export.dart';
import 'package:kazumi/services/phone_keyboard_session.dart';

void main() {
  test('sharing copy removes common secrets while retaining failure evidence',
      () {
    final raw = '''02:01:02.111 ERROR PlaybackTrace decoder_failed retry=2
Authorization: Bearer auth-secret
Cookie: session=cookie-secret; private=more-secret
{"token":"json-secret with spaces","password":"pass-secret","code":429}
用户名: user-secret 账号=account-secret
https://user:pass@192.168.1.2/video.m3u8?token=url-secret
https%253A%252F%252Fexample.com%252Fprivate%253Ftoken%253Dencoded-secret
contact person@example.com
peer 192.168.1.2 deviceId=device-secret android_id=android-secret
oauth_token=oauth-secret client_secret=client-secret accessKey=access-secret
peer ::1 fe80::dead:beef
path \\\\server-secret\\share\\file
path C:\\Users\\private-person\\logs\\a.txt
path /data/user/0/app/private-file
pair 0123456789abcdef0123456789abcdef
at package:kazumi/services/player.dart:123:4
''';
    final text = formatLogExport(raw,
        createdAt: DateTime.utc(2026, 10, 31),
        version: '0.4.6',
        platform: 'android');
    for (final secret in [
      'auth-secret',
      'cookie-secret',
      'more-secret',
      'json-secret',
      'pass-secret',
      'user-secret',
      'account-secret',
      'url-secret',
      'encoded-secret',
      'person@example.com',
      '192.168.1.2',
      'device-secret',
      'android-secret',
      'oauth-secret',
      'client-secret',
      'access-secret',
      '::1',
      'fe80::dead:beef',
      'server-secret',
      'private-person',
      'private-file',
      '0123456789abcdef0123456789abcdef'
    ]) {
      expect(text, isNot(contains(secret)), reason: secret);
    }
    expect(text, contains('decoder_failed retry=2'));
    expect(text, contains('"code":429'));
    expect(text, contains('package:kazumi/services/player.dart:123:4'));
    expect(text, contains('02:01:02.111'));
    expect(raw, contains('auth-secret')); // original is untouched
  });

  test('UTF-8 export and filenames remain bounded, empty logs are explicit',
      () {
    final time = DateTime.utc(2026, 10, 31, 12, 34, 56);
    final text = formatLogExport('日志' * 400000,
        createdAt: time, version: '0.4.6', platform: 'android');
    final snapshot = LogExport(text: text, createdAt: time);
    expect(utf8.encode(snapshot.text).length,
        lessThanOrEqualTo(LogExport.maxBytes));
    expect(snapshot.text, contains('较早内容已省略'));
    expect(snapshot.filename, matches(r'^kazumitv-log-[0-9TZ]+\.txt$'));
    expect(
        () => LogExport(text: 'x' * (LogExport.maxBytes + 1), createdAt: time),
        throwsArgumentError);
    expect(
        formatLogExport('',
            createdAt: time, version: 'unknown', platform: 'android'),
        contains('暂无应用日志'));
  });

  group('paired transport', () {
    late PhoneKeyboardSession session;
    late HttpClient client;
    late Uri base;
    final snapshot = LogExport(
        text: '已遮盖的日志\n失败：decoder_failed',
        createdAt: DateTime.utc(2026, 10, 31));
    setUp(() async {
      session = PhoneKeyboardSession();
      client = HttpClient();
      base = await session.start(address: InternetAddress.loopbackIPv4);
    });
    tearDown(() async {
      client.close(force: true);
      await session.close();
    });
    Future<(int, String, HttpHeaders)> get(String path,
        {String? origin}) async {
      final request = await client.getUrl(base.replace(path: path));
      if (origin != null) request.headers.set('Origin', origin);
      final result = await request.close();
      return (
        result.statusCode,
        await utf8.decodeStream(result),
        result.headers
      );
    }

    String logPath() => '${base.path}/logs/${session.logExportState!['id']}';

    test(
        'pairing alone exposes no logs; published state contains metadata only',
        () async {
      expect(session.state['logExport'], isNull);
      expect((await get('${base.path}/logs')).$1, 404);
      expect(
          (await get('${base.path}/logs/../../logs/kazumi_logs.log')).$1, 404);
      session.publishLogExport(snapshot);
      final state = await get('${base.path}/state');
      expect(state.$2, isNot(contains('decoder_failed')));
      final result = await get(logPath(), origin: base.origin);
      expect(result.$1, 200);
      expect(result.$2, snapshot.text);
      expect(result.$3.contentType?.mimeType, 'text/plain');
      expect(
          result.$3.value('content-disposition'), contains(snapshot.filename));
      expect(result.$3.value('cache-control'), 'no-store');
      expect(session.readTextAllowed, false);
    });

    test('wrong token, guessed ID and cross-origin cannot retrieve a snapshot',
        () async {
      session.publishLogExport(snapshot);
      expect((await get(logPath().replaceFirst(base.path, '/wrong'))).$1, 404);
      expect((await get('${base.path}/logs/guessed')).$1, 404);
      expect(
          (await get(logPath(), origin: 'https://untrusted.invalid')).$1, 403);
      expect((await get(logPath())).$1, 200);
    });

    test(
        'replacement and revoke invalidate old addresses without altering pairing',
        () async {
      session.publishLogExport(snapshot);
      final old = logPath();
      session.publishLogExport(snapshot);
      expect(logPath(), isNot(old));
      expect((await get(old)).$1, 404);
      final active = logPath();
      session.revokeLogExport();
      expect(session.state['logExport'], isNull);
      expect((await get(active)).$1, 404);
      expect((await get('${base.path}/state')).$1, 200);
    });

    test(
        'expiry releases the snapshot and heartbeat cannot extend export lifetime',
        () async {
      session.publishLogExport(snapshot,
          lifetime: const Duration(milliseconds: 60));
      final path = logPath();
      await get('${base.path}/state');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(session.logExportState, isNull);
      expect((await get(path)).$1, 404);
    });

    test(
        'closing and reusing a remembered token does not restore log capability',
        () async {
      session.publishLogExport(snapshot);
      final oldId = session.logExportState!['id'];
      final token = session.token;
      await session.close();
      expect(session.state['logExport'], isNull);
      session = PhoneKeyboardSession(accessToken: token);
      base = await session.start(address: InternetAddress.loopbackIPv4);
      expect((await get('${base.path}/logs/$oldId')).$1, 404);
      expect(
          () => session.publishLogExport(snapshot,
              lifetime: const Duration(days: 1)),
          throwsStateError);
    });
  });
}
