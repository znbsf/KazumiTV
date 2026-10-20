import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tools/qa/source_batch/chapter_diagnostic_runtime.dart';

void spinWorker(List<Object?> input) {
  while (true) {}
}

void invalidReplyWorker(List<Object?> input) {
  (input[0] as SendPort).send('PRIVATE_SENTINEL');
}

void main() {
  const url = 'https://www.moonci.com/PRIVATE_SENTINEL';
  const raw =
      '<html><head><title>葬送的芙莉莲 - fixture</title></head><ul><li><a href="/one">第01话</a></li></ul></html>';
  final hash = sha256.convert(utf8.encode(url)).toString();
  Response<String> response(
          {int status = 200,
          String mime = 'text/html; charset=utf-8',
          String body = raw,
          String requestUrl = url,
          bool redirect = false,
          bool challenge = false}) =>
      Response(
          data: body,
          requestOptions: RequestOptions(path: requestUrl),
          statusCode: status,
          isRedirect: redirect,
          headers: Headers.fromMap({
            Headers.contentTypeHeader: [mime],
            'authorization': ['Bearer PRIVATE_SENTINEL'],
            'set-cookie': ['PRIVATE_SENTINEL'],
            if (challenge) 'cf-mitigated': ['challenge']
          }));

  test(
      'passive valid response is bound to exactly the original String and closes its own interceptor',
      () {
    final dio = Dio();
    final tap = QaChapterResponseTap(dio, hash);
    final r = response();
    final handler = ResponseInterceptorHandler();
    tap.onResponse(r, handler);
    expect(handler.isCompleted, true);
    expect(tap.rejection(raw), isNull);
    expect(tap.rejection('$raw changed'), 'response_body_mismatch');
    expect(jsonEncode(tap.metadata), isNot(contains('PRIVATE_SENTINEL')));
    expect(r.data, raw);
    expect(r.requestOptions.path, url);
    expect(tap.close(), true);
    expect(dio.interceptors.contains(tap), false);
    tap.observe(r);
    expect(tap.metadata['response_count'], 1);
    dio.close();
  });
  test(
      'HTTP/MIME/redirect/challenge/size/identity preconditions stop before any comparison',
      () {
    final variants = [
      response(status: 403),
      response(mime: 'text/plain'),
      response(redirect: true),
      response(challenge: true),
      response(body: 'x' * (256 * 1024 + 1)),
      response(requestUrl: '$url-other'),
      response(body: '<html><title>Just a moment</title></html>')
    ];
    for (final r in variants) {
      final dio = Dio();
      final tap = QaChapterResponseTap(dio, hash)..observe(r);
      expect(tap.rejection(r.data!), isNotNull);
      expect(tap.close(), true);
      dio.close();
    }
  });
  test(
      'missing and duplicate metadata are never treated as a valid detail response',
      () {
    final dio = Dio();
    final tap = QaChapterResponseTap(dio, hash);
    expect(tap.rejection(raw), 'no_unique_detail_response');
    tap.observe(response());
    tap.observe(response());
    expect(tap.rejection(raw), 'no_unique_detail_response');
    tap.close();
    dio.close();
  });
  test('strict aafun input/rule binding cannot be enabled for another case',
      () {
    final config = <String, dynamic>{
      'id': 'inventory-aafun-q2-selector-diagnostic',
      'selection_only': true,
      'engine': 'app',
      'keyword': '葬送的芙莉莲'
    };
    final rule = <String, Object?>{
      'name': 'aafun',
      'version': '1.2',
      'effective_sha256': aafunRuleSha,
      'variant': 'effective',
      'overlay': false
    };
    expect(aafunDiagnosticBinding(config, rule), true);
    expect(aafunDiagnosticBinding({...config, 'selection_only': false}, rule),
        false);
    expect(
        aafunDiagnosticBinding(config, {...rule, 'effective_sha256': 'wrong'}),
        false);
    expect(aafunDiagnosticBinding({...config, 'id': 'another'}, rule), false);
  });
  test(
      'actual comparison completes in an isolate without returning raw HTML or URI',
      () async {
    final base = <String, dynamic>{
      'api': '4',
      'name': 'aafun',
      'version': '1.2',
      'baseURL': 'https://www.moonci.com/',
      'chapterRoads': '//ul',
      'chapterResult': './/a'
    };
    final result = await boundedQaWorker(
        worker: chapterSelectorWorker,
        input: {'raw': raw, 'base': base, 'semantic': base},
        remainingBudget: const Duration(seconds: 5),
        isCancelled: () => false);
    expect(result['status'], 'observed');
    expect(result['worker_cleanup'], 'confirmed');
    expect(jsonEncode(result), isNot(contains('<html>')));
    expect(jsonEncode(result), isNot(contains('https://www.moonci.com/')));
  });
  test('CPU-hung worker times out, is killed, and acknowledges exit', () async {
    final result = await boundedQaWorker(
        worker: spinWorker,
        input: {},
        remainingBudget: const Duration(milliseconds: 600),
        isCancelled: () => false);
    expect(result['status'], 'not_run');
    expect(result['reason'], 'worker_timeout');
    expect(result['worker_cleanup'], 'confirmed');
    expect(result['worker_elapsed_ms'] as int, lessThan(1200));
  });
  test('HTTP200 wrong-work and soft404 titles never enter selector comparison',
      () async {
    for (final html in [
      '<html><title>Another work</title></html>',
      '<html><title>404 error 葬送的芙莉莲</title></html>'
    ]) {
      final result = await boundedQaWorker(
          worker: chapterSelectorWorker,
          input: {'raw': html, 'base': {}, 'semantic': {}},
          remainingBudget: const Duration(seconds: 2),
          isCancelled: () => false);
      expect(result['status'], 'not_run');
      expect(result['reason'], 'work_title_not_confirmed');
      expect(result['worker_cleanup'], 'confirmed');
    }
  });
  test('cancellation kills a running worker and discards any comparison result',
      () async {
    var cancelled = false;
    final timer =
        Timer(const Duration(milliseconds: 80), () => cancelled = true);
    try {
      final result = await boundedQaWorker(
          worker: spinWorker,
          input: {},
          remainingBudget: const Duration(seconds: 2),
          isCancelled: () => cancelled);
      expect(result['status'], 'not_run');
      expect(result['reason'], 'cancelled');
      expect(result['worker_cleanup'], 'confirmed');
    } finally {
      timer.cancel();
    }
  });
  test('no budget or cancellation before spawn creates no worker', () async {
    final result = await boundedQaWorker(
        worker: spinWorker,
        input: {},
        remainingBudget: Duration.zero,
        isCancelled: () => false);
    expect(result['worker_cleanup'], 'not_created');
  });
  test('invalid worker reply is typed and never exports the reply value',
      () async {
    final result = await boundedQaWorker(
        worker: invalidReplyWorker,
        input: {},
        remainingBudget: const Duration(seconds: 2),
        isCancelled: () => false);
    expect(result['reason'], 'invalid_worker_reply');
    expect(result['worker_cleanup'], 'confirmed');
    expect(jsonEncode(result), isNot(contains('PRIVATE_SENTINEL')));
  });
}
