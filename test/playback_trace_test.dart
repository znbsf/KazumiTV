import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/logging/playback_trace.dart';
import 'package:kazumi/services/player/player_error_mapper.dart';

void main() {
  test('failure retains unknown native detail before synchronous retirement',
      () {
    final records = <String>[];
    final trace = PlaybackTrace('native', sink: records.add);
    var current = true;
    trace.event('mpv_error',
        detail: 'ffmpeg: TLS connection reset, errno -101');
    PlayerErrorMapper.dispatchCurrentError('Demuxer failed: custom error -123',
        isCurrent: () => current,
        record: (_) => trace.finish('native_error',
            error: 'Demuxer failed: custom error -123'),
        handle: (_) {
          current = false;
          trace.finish('disposed');
        });
    final entry = jsonDecode(records.single) as Map;
    expect(entry['error'], contains('custom error -123'));
    expect(entry['events'].single['detail'], contains('errno -101'));
    trace.event('late', detail: 'must not contaminate');
    trace.finish('another failure');
    expect(records, hasLength(1));
  });

  test('redacts signed URLs, encoded URLs and credentials before persistence',
      () {
    const url =
        'https://user:pass@cdn.test/private/path?sign=TOPSECRET#fragment';
    final safe =
        PlaybackTrace.safeDetail('HTTP 403 $url ${Uri.encodeComponent(url)}\n'
            'Authorization: Bearer PRIVATEVALUE\nCookie: sid=PRIVATECOOKIE\n'
            'token=PRIVATEKEY handshake failed (-101)');
    for (final value in ['TOPSECRET', 'PRIVATE', 'user', 'pass', 'fragment']) {
      expect(safe, isNot(contains(value)));
    }
    expect(safe, contains('HTTP 403'));
    expect(safe, contains('handshake failed (-101)'));
    expect(PlaybackTrace.resource(url), startsWith('cdn.test#'));
    expect(PlaybackTrace.resource(url), isNot(contains('TOPSECRET')));
    expect(PlaybackTrace.resource(url), PlaybackTrace.resource(url));
  });

  test('keeps request identity and bounded recent context without flooding',
      () {
    final records = <String>[];
    final trace = PlaybackTrace('parser', sink: records.add);
    trace.event('load', url: 'https://page.test/private?token=secret');
    for (var i = 0; i < 100; i++) {
      trace.event('error_$i', detail: List.filled(2000, 'x ').join());
    }
    trace.finish('timeout');
    final events = (jsonDecode(records.single) as Map)['events'] as List;
    expect(events, hasLength(PlaybackTrace.maxEvents));
    expect(events.first['stage'], 'load');
    expect(events.last['stage'], 'error_99');
    expect(records.single.length, lessThan(10000));
  });

  test('a logging failure does not throw into playback and sessions differ',
      () {
    final a = PlaybackTrace('parser', sink: (_) => throw StateError('disk'));
    final b = PlaybackTrace('parser', sink: (_) {});
    expect(a.id, isNot(b.id));
    expect(() => a.finish('failed', error: 'network'), returnsNormally);
  });
}
