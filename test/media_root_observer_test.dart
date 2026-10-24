import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../tools/qa/source_batch/media_root_observer.dart';

const qaPackage = 'com.znbsf.kazumi.fluttertv.parserqa';

Future<Map<String, Object?>> inspect(String url,
        {bool Function()? cancelled,
        Duration budget = const Duration(seconds: 2)}) =>
    observeMediaRoot(
        enabled: true,
        debug: true,
        packageName: qaPackage,
        mediaUrl: url,
        headers: {
          'User-Agent': 'ACTUAL_UA_SENTINEL',
          'Referer': 'https://example.invalid/private?value=REF_SENTINEL',
          'Cookie': 'COOKIE_SENTINEL',
          'Authorization': 'AUTH_SENTINEL',
        },
        isCancelled: cancelled ?? () => false,
        budget: budget);

Future<void> fixture(Future<void> Function(HttpRequest request) serve,
    Future<void> Function(String base) action) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final subscription = server.listen((request) async {
    try {
      await serve(request);
    } catch (_) {
      // Closing the client mid-body is a deliberate cancellation fixture.
    }
  });
  try {
    await action('http://127.0.0.1:${server.port}');
  } finally {
    await server.close(force: true);
    await subscription.cancel();
  }
}

void main() {
  test('disabled or wrong QA identity cannot start a request', () async {
    expect(
        await observeMediaRoot(
            enabled: false,
            debug: false,
            packageName: 'normal',
            mediaUrl: 'invalid',
            headers: {},
            isCancelled: () => false),
        {'enabled': false});
    await expectLater(
        observeMediaRoot(
            enabled: true,
            debug: false,
            packageName: qaPackage,
            mediaUrl: 'invalid',
            headers: {},
            isCancelled: () => false),
        throwsStateError);
  });

  test('root and child HTTP failures remain distinct without leaking context',
      () async {
    final paths = <String>[];
    await fixture((request) async {
      paths.add(request.uri.path);
      expect(request.headers.value('cookie'), isNull);
      expect(request.headers.value('authorization'), isNull);
      expect(request.headers.value('user-agent'), 'ACTUAL_UA_SENTINEL');
      expect(request.headers.value('range'), 'bytes=0-65535');
      if (request.uri.path == '/root') {
        request.response.write('#EXTM3U\n#EXTINF:1,\nchild.ts');
      } else {
        request.response.statusCode = 404;
        request.response.write('PRIVATE_BODY_SENTINEL');
      }
      await request.response.close();
    }, (base) async {
      final result = await inspect('$base/root');
      final rows = result['observations'] as List;
      expect(rows.map((row) => row['status']), [200, 404]);
      expect(rows.map((row) => row['role']), ['root', 'child']);
      expect(result['outcome'], 'observed');
      expect(jsonEncode(result), isNot(contains('SENTINEL')));
      expect(jsonEncode(result), isNot(contains('/root')));
      expect(jsonEncode(result), isNot(contains('child.ts')));
    });
    expect(paths, ['/root', '/child.ts']);
  });

  test('server ignoring Range cannot cause an unbounded buffered response',
      () async {
    await fixture((request) async {
      request.response.write('x' * 200000);
      await request.response.close();
    }, (base) async {
      final result = await inspect('$base/large');
      final row = (result['observations'] as List).single;
      expect(row['buffered_bytes'], 65536);
      expect(row['body_limit_reached'], true);
      expect(result['stop_reason'], 'body_limit');
    });
  });

  test('challenge and redirect do not produce additional requests', () async {
    for (final redirect in [false, true]) {
      var count = 0;
      await fixture((request) async {
        count++;
        request.response.statusCode = redirect ? 302 : 403;
        request.response.headers.set(redirect ? 'location' : 'cf-mitigated',
            redirect ? '/redirect?sign=SENTINEL' : 'challenge');
        request.response.write('#EXTM3U\nchild.ts');
        await request.response.close();
      }, (base) async {
        final result = await inspect('$base/root');
        expect((result['observations'] as List).length, 1);
        expect(jsonEncode(result), isNot(contains('SENTINEL')));
      });
      expect(count, 1);
    }
  });

  test('ambiguous list never probes one of several possible children',
      () async {
    var count = 0;
    await fixture((request) async {
      count++;
      request.response.write('#EXTM3U\na.ts\nb.ts');
      await request.response.close();
    }, (base) async {
      final result = await inspect('$base/root');
      expect(result['stop_reason'], 'no_unique_child');
    });
    expect(count, 1);
  });

  test('stalled body shares the global deadline and closes transport',
      () async {
    final release = Completer<void>();
    try {
      await fixture((request) async {
        request.response.write('#EXTM3U\n');
        await request.response.flush();
        await release.future;
        await request.response.close();
      }, (base) async {
        final result = await inspect('$base/stall',
            budget: const Duration(milliseconds: 100));
        expect(result['outcome'], 'timeout');
        expect((result['observations'] as List).length, 1);
      });
    } finally {
      release.complete();
    }
  });

  test('a second playlist cannot trigger a third HTTP request', () async {
    var count = 0;
    await fixture((request) async {
      count++;
      request.response
          .write('#EXTM3U\n${count == 1 ? 'child.m3u8' : 'third.ts'}');
      await request.response.close();
    }, (base) async {
      final result = await inspect('$base/root');
      expect((result['observations'] as List).length, 2);
      expect(result['stop_reason'], 'request_limit');
    });
    expect(count, 2);
  });

  test('TLS negotiation failure exports only error type, never its request URI',
      () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    final listener = server.listen((socket) {
      sockets.add(socket);
      socket.add(ascii.encode('HTTP/1.1 400 Bad Request\r\n\r\n'));
      unawaited(socket.flush().then((_) => socket.destroy()));
    });
    try {
      final result = await inspect(
          'https://127.0.0.1:${server.port}/TLS_SENTINEL?fixture=QUERY_SENTINEL');
      expect(result['outcome'], 'transport_error');
      expect(result['error_type'], isNotNull);
      expect(jsonEncode(result), isNot(contains('SENTINEL')));
    } finally {
      for (final socket in sockets) {
        socket.destroy();
      }
      await server.close();
      await listener.cancel();
    }
  });

  test('cancellation while reading cannot proceed to a child', () async {
    var cancelled = false;
    final release = Completer<void>();
    try {
      await fixture((request) async {
        request.response.write('#EXTM3U\n');
        await request.response.flush();
        cancelled = true;
        await release.future;
        await request.response.close();
      }, (base) async {
        final result =
            await inspect('$base/cancel', cancelled: () => cancelled);
        expect(result['outcome'], 'cancelled');
        expect((result['observations'] as List).length, 1);
      });
    } finally {
      release.complete();
    }
  });
}
