import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import '../tools/qa/source_batch/media_response_analysis.dart';

MediaResponseAnalysis analyze(String body,
        {int status = 200,
        String url = 'https://source.test/path/index.m3u8',
        bool cancelled = false,
        Duration remaining = const Duration(seconds: 10),
        int count = 1}) =>
    analyzeMediaResponse(
        requestUrl: url,
        status: status,
        contentType: 'application/vnd.apple.mpegurl',
        body: Uint8List.fromList(utf8.encode(body)),
        observedAt: DateTime.utc(2026, 10, 20),
        cancelled: cancelled,
        remainingBudget: remaining,
        requestsAlreadyObserved: count);

void main() {
  test(
      'unknown tag names and signed redirects never export raw response values',
      () {
    final parsed = analyze('#EXTM3U\n#AUTH-SENTINEL:value\nchild.ts');
    expect(parsed.toString(), isNot(contains('SENTINEL')));
    expect(parsed.publicRecord['hls_tags'], contains('OTHER_TAG'));
    final redirected = analyzeMediaResponse(
        requestUrl: 'https://source.test/root',
        status: 302,
        contentType: 'text/html',
        body: Uint8List(0),
        observedAt: DateTime.utc(2026, 10, 20),
        redirectLocation: '/PRIVATE_SENTINEL?sign=SIGNED_SENTINEL');
    expect(redirected.toString(), isNot(contains('SENTINEL')));
    expect(redirected.childUrlInMemory, isNull);
    expect(redirected.publicRecord['stop_reason'], 'redirect_not_followed');
  });

  test('MP4 and nested URL query are terminal without exporting payload', () {
    final mp4 = analyzeMediaResponse(
        requestUrl: 'https://source.test/movie.mp4',
        status: 206,
        contentType: 'video/mp4',
        body: Uint8List.fromList([0, 0, 0, 20, ...ascii.encode('ftypisom')]),
        observedAt: DateTime.utc(2026, 10, 20));
    expect(mp4.publicRecord['structure'], 'mp4');
    expect(mp4.childUrlInMemory, isNull);
    expect(
        mediaObservationStopReason(
            'https://source.test/api?url=https%3A%2F%2Fother.test%2Fvideo'),
        'nested_url_query');
  });

  test(
      'root404 and child404 remain distinct observations; neither follows a child',
      () {
    final root = analyze('#EXTM3U\nchild.ts', status: 404);
    final child = analyze('Not Found',
        status: 404, url: 'https://source.test/path/child.ts', count: 2);
    expect(root.publicRecord['status'], 404);
    expect(child.publicRecord['status'], 404);
    expect(
        root.publicRecord['resource'], isNot(child.publicRecord['resource']));
    expect(root.childUrlInMemory, isNull);
    expect(child.childUrlInMemory, isNull);
  });

  test(
      'only one unambiguous unsigned child is eligible, expanded only in memory',
      () {
    final parsed = analyze('#EXTM3U\n#EXTINF:1,\nchild.ts');
    expect(parsed.childUrlInMemory, 'https://source.test/path/child.ts');
    expect(parsed.publicRecord['hls_tags'], ['EXTINF', 'EXTM3U']);
    expect(parsed.toString(), isNot(contains('/path/')));
    expect(parsed.toString(), isNot(contains('child.ts')));
    expect(analyze('#EXTM3U\na.ts\nb.ts').childUrlInMemory, isNull);
    expect(analyze('#EXTM3U\nindex.m3u8').publicRecord['stop_reason'], 'cyclic_child');
  });

  test(
      'signature, challenge, HTML, encryption attributes and redirects stop traversal',
      () {
    for (final value in [
      analyze('#EXTM3U\nchild.ts?sign=SIGNED_SENTINEL'),
      analyze('#EXTM3U\nchild.ts?X-Goog-Signature=SIGNED_SENTINEL'),
      analyze('#EXTM3U\nchild.ts?auth_key=SIGNED_SENTINEL'),
      analyze('<html><title>Just a moment</title>SECRET_SENTINEL</html>'),
      analyze('<html>PRIVATE_SENTINEL</html>'),
      analyze(
          '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="KEY_SENTINEL"\nchild.ts'),
      analyze('#EXTM3U\nchild.ts', status: 302),
      analyze('#EXTM3U\nchild.ts',
          url: 'https://source.test/root?token=ROOT_SENTINEL'),
    ]) {
      expect(value.childUrlInMemory, isNull);
      expect(value.toString(), isNot(contains('SENTINEL')));
    }
  });

  test(
      'buffer cap, cancellation, shared budget and second-observation limit stop traversal',
      () {
    final huge = analyze('#EXTM3U\n${'x' * 100000}');
    expect(huge.publicRecord['buffered_bytes'], mediaObservationByteLimit);
    expect(huge.childUrlInMemory, isNull);
    expect(
        analyze('#EXTM3U\nchild.ts', cancelled: true).childUrlInMemory, isNull);
    expect(
        analyze('#EXTM3U\nchild.ts', remaining: Duration.zero).childUrlInMemory,
        isNull);
    expect(analyze('#EXTM3U\nchild.ts', count: 2).childUrlInMemory, isNull);
  });
}
