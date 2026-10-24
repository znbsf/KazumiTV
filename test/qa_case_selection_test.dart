import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tools/qa/source_batch/case_selection.dart';

void main() {
  const url = 'https://example.invalid/alternate-episode-1';
  final config = <String, dynamic>{
    'expected_episode_page_sha256': sha256.convert(utf8.encode(url)).toString(),
    'expected_episode_label': '第1集',
  };
  test('exact alternate page and label are accepted independent of road index',
      () {
    expect(qaEpisodeMatches(config, url: url, label: '第1集'), true);
    expect(qaEpisodeMatches(config, url: '$url-wrong', label: '第1集'), false);
    expect(qaEpisodeMatches(config, url: url, label: '第2集'), false);
  });
  test('partial or malformed binding is rejected rather than silently ignored',
      () {
    for (final bad in [
      {'expected_episode_label': '第1集'},
      {'expected_episode_page_sha256': 'not-a-digest'},
      {'expected_episode_page_sha256': config['expected_episode_page_sha256']},
    ]) {
      expect(() => qaEpisodeMatches(bad, url: url, label: '第1集'),
          throwsFormatException);
    }
  });
  test(
      'ordinary QA cases retain their existing selection when no binding requested',
      () {
    expect(qaEpisodeMatches({}, url: url, label: '第1集'), true);
  });
}
