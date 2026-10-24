import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../tools/qa/source_batch/media_context_summary.dart';

Map<String, Object?> summary(
        {Map<String, String>? headers, String caseId = 'qa-case'}) =>
    mediaContextPublicSummary(
      caseId: caseId,
      ruleSha256: 'a' * 64,
      episodeUrl: 'https://episode.test/private-episode?token=EPISODE_SENTINEL',
      mediaUrl: 'https://media.test/private-file?sign=SIGNED_SENTINEL',
      headers: headers ??
          {
            'User-Agent': 'UA_SENTINEL',
            'Referer': 'https://referer.test/path?token=REFERER_SENTINEL',
            'Authorization': 'AUTH_SENTINEL',
            'Cookie': 'COOKIE_SENTINEL',
          },
      observedAt: DateTime.utc(2026, 10, 20),
    );

void main() {
  test('metadata defaults off; debug and exact QA identity are both required',
      () {
    expect(
        qaMediaMetadataEnabled(
            enabled: false, debug: false, packageName: 'normal'),
        isFalse);
    for (final flags in [
      (false, 'com.znbsf.kazumi.fluttertv.parserqa'),
      (true, 'normal')
    ]) {
      expect(
          () => qaMediaMetadataEnabled(
              enabled: true, debug: flags.$1, packageName: flags.$2),
          throwsStateError);
    }
    expect(
        qaMediaMetadataEnabled(
            enabled: true,
            debug: true,
            packageName: 'com.znbsf.kazumi.fluttertv.parserqa'),
        isTrue);
  });

  test(
      'only hosts and hashes leave the summary; no secret sentinels or raw paths',
      () {
    final value = summary();
    final text = jsonEncode(value);
    expect(text, isNot(contains('SENTINEL')));
    expect(text, isNot(contains('private-')));
    expect(text, isNot(contains('referer.test')));
    expect(value['header_names'], ['referer', 'user-agent']);
    expect(value['expires_at_utc'], isNull);
    expect(value['expiry_basis'], 'unknown');
    expect(value['private_context_saved'], isFalse);
  });

  test('non-allowlisted values have no effect on exported fingerprint', () {
    final a = summary(headers: {'User-Agent': 'same', 'Cookie': 'FIRST'});
    final b =
        summary(headers: {'user-agent': 'same', 'Authorization': 'SECOND'});
    expect(a, b);
  });

  test('invalid identities and duplicate headers fail without echoing values',
      () {
    try {
      summary(caseId: '../../SIGNED_SENTINEL');
      fail('accepted invalid id');
    } catch (error) {
      expect(error, isA<FormatException>());
      expect('$error', isNot(contains('SENTINEL')));
    }
    expect(
        () => summary(headers: {'User-Agent': 'FIRST', 'user-agent': 'SECOND'}),
        throwsFormatException);
  });
}
