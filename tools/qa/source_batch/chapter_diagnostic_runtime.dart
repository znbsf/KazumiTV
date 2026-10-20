// QA-only passive response metadata and bounded, killable CPU comparison.
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'chapter_selector_diagnostic.dart';

const aafunRuleSha =
    '0968af776817005f76377a8e58df54027458ef2baa199c2cb7d35bef03bae0c7';
const aafunDetailSha =
    '8242833086894f4ecfea3aa4206d65519295f41da83e40560a90d5164b71f026';
const aafunEpisodeSha =
    'f63fd948d18e62223d02057b7c6637d4436b793f34a031f1ca4bd4cf9b2a7355';

bool aafunDiagnosticBinding(
        Map<String, dynamic> config, Map<String, Object?> rule) =>
    config['id'] == 'inventory-aafun-q2-selector-diagnostic' &&
    config['selection_only'] == true &&
    config['engine'] == 'app' &&
    config['keyword'] == '葬送的芙莉莲' &&
    rule['name'] == 'aafun' &&
    rule['version'] == '1.2' &&
    rule['effective_sha256'] == aafunRuleSha &&
    rule['overlay'] == false &&
    rule['variant'] == 'effective';

class QaChapterResponseTap extends Interceptor {
  QaChapterResponseTap(this.dio, this.expectedRequestSha) {
    dio.interceptors.add(this);
  }
  final Dio dio;
  final String expectedRequestSha;
  final metadata = <String, Object?>{'response_count': 0};
  String? _bodySha;
  bool _closed = false;
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    observe(response);
    handler.next(response);
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) {
    final response = error.response;
    if (response != null) observe(response);
    if (!_closed) metadata['transport_error_type'] = error.type.name;
    handler.next(error);
  }

  void observe(Response response) {
    if (_closed) return;
    metadata['response_count'] = (metadata['response_count'] as int) + 1;
    try {
      final requestHash = sha256
          .convert(utf8.encode(response.requestOptions.uri.toString()))
          .toString();
      metadata['request_sha256'] = requestHash;
      metadata['status'] = response.statusCode;
      metadata['redirected'] =
          response.redirects.isNotEmpty || response.isRedirect;
      metadata['real_uri_sha256'] =
          sha256.convert(utf8.encode(response.realUri.toString())).toString();
      final mime = (response.headers.value(Headers.contentTypeHeader) ?? '')
          .split(';')
          .first
          .trim()
          .toLowerCase();
      metadata['html_mime'] =
          {'text/html', 'application/xhtml+xml'}.contains(mime);
      metadata['challenge'] =
          response.headers.value('cf-mitigated')?.toLowerCase() == 'challenge';
      final data = response.data;
      if (requestHash != expectedRequestSha || data is! String) return;
      if (data.length > ChapterSelectorDiagnostic.maxHtmlBytes) {
        metadata['body_size_limit'] = true;
        return;
      }
      final bytes = utf8.encode(data);
      metadata['body_utf8_bytes'] = bytes.length;
      metadata['body_size_limit'] =
          bytes.length > ChapterSelectorDiagnostic.maxHtmlBytes;
      if (metadata['body_size_limit'] == true) return;
      _bodySha = sha256.convert(bytes).toString();
      metadata['body_sha256'] = _bodySha;
      final text = data.toLowerCase();
      metadata['challenge'] = metadata['challenge'] == true ||
          text.contains('window._cf_chl_opt') ||
          text.contains('challenge-platform') ||
          text.contains('<title>just a moment');
    } catch (error) {
      metadata['metadata_error_type'] = error.runtimeType.toString();
    }
  }

  String? rejection(String raw) {
    if (metadata['metadata_error_type'] != null) return 'metadata_unusable';
    if (metadata['response_count'] != 1) return 'no_unique_detail_response';
    if (metadata['request_sha256'] != expectedRequestSha ||
        metadata['real_uri_sha256'] != expectedRequestSha) {
      return 'detail_identity_mismatch';
    }
    final status = metadata['status'];
    if (status is! int || status < 200 || status >= 300) return 'http_status';
    if (metadata['redirected'] != false) return 'redirected';
    if (metadata['html_mime'] != true) return 'not_html';
    if (metadata['challenge'] == true) return 'challenge';
    if (metadata['body_size_limit'] == true ||
        raw.length > ChapterSelectorDiagnostic.maxHtmlBytes) {
      return 'body_size_limit';
    }
    if (raw.trim().isEmpty || _bodySha == null) return 'empty_or_missing_body';
    final bytes = utf8.encode(raw);
    if (bytes.length > ChapterSelectorDiagnostic.maxHtmlBytes) {
      return 'body_size_limit';
    }
    if (sha256.convert(bytes).toString() != _bodySha) {
      return 'response_body_mismatch';
    }
    return null;
  }

  bool close() {
    _closed = true;
    try {
      dio.interceptors.remove(this);
      return !dio.interceptors.contains(this);
    } catch (error) {
      metadata['interceptor_close_error_type'] = error.runtimeType.toString();
      return false;
    }
  }
}

void chapterSelectorWorker(List<Object?> message) {
  final output = message[0] as SendPort;
  final input = Map<String, dynamic>.from(message[1] as Map);
  try {
    final raw = input['raw'] as String;
    if (raw.length > ChapterSelectorDiagnostic.maxHtmlBytes ||
        utf8.encode(raw).length > ChapterSelectorDiagnostic.maxHtmlBytes) {
      output.send({'status': 'not_run', 'reason': 'body_size_limit'});
      return;
    }
    final lower = raw.toLowerCase();
    final opening = lower.indexOf('<title');
    final begin = opening < 0 ? -1 : lower.indexOf('>', opening);
    final end = begin < 0 ? -1 : lower.indexOf('</title>', begin);
    final title = begin >= 0 && end > begin && end - begin <= 512
        ? raw.substring(begin + 1, end)
        : '';
    if (!title.contains('葬送的芙莉莲') ||
        RegExp(r'404|not found|error|禁止访问|页面不存在', caseSensitive: false)
            .hasMatch(title)) {
      output.send({'status': 'not_run', 'reason': 'work_title_not_confirmed'});
      return;
    }
    output.send(ChapterSelectorDiagnostic.compare(
        rawHtml: raw,
        baseRuleJson: Map<String, dynamic>.from(input['base'] as Map),
        semanticRuleJson: Map<String, dynamic>.from(input['semantic'] as Map),
        expectedEpisodeSha256: aafunEpisodeSha,
        expectedEpisodeLabel: '第01话')
      ..['work_title_confirmed'] = true);
  } catch (error) {
    output.send({
      'status': 'not_run',
      'reason': 'worker_error',
      'error_type': error.runtimeType.toString()
    });
  }
}

Future<Map<String, Object?>> boundedQaWorker({
  required void Function(List<Object?>) worker,
  required Map<String, Object?> input,
  required Duration remainingBudget,
  required bool Function() isCancelled,
}) async {
  bool cancelled() {
    try {
      return isCancelled();
    } catch (_) {
      return true;
    }
  }

  if (cancelled() || remainingBudget <= Duration.zero) {
    return {
      'status': 'not_run',
      'reason': 'cancelled_or_no_budget',
      'worker_cleanup': 'not_created'
    };
  }
  final total = remainingBudget < const Duration(seconds: 5)
      ? remainingBudget
      : const Duration(seconds: 5);
  final reserve = total < const Duration(milliseconds: 750)
      ? Duration(microseconds: total.inMicroseconds ~/ 3)
      : const Duration(milliseconds: 500);
  final workBudget = total - reserve;
  final clock = Stopwatch()..start();
  final replies = ReceivePort(), errors = ReceivePort(), exits = ReceivePort();
  final answer = Completer<Map<String, Object?>>(), exited = Completer<void>();
  final subscriptions = <StreamSubscription>[
    replies.listen((value) {
      if (answer.isCompleted) return;
      try {
        answer.complete(Map<String, Object?>.from(value as Map));
      } catch (_) {
        answer
            .complete({'status': 'not_run', 'reason': 'invalid_worker_reply'});
      }
    }),
    errors.listen((_) {
      if (!answer.isCompleted) {
        answer.complete({'status': 'not_run', 'reason': 'worker_error'});
      }
    }),
    exits.listen((_) {
      if (!exited.isCompleted) exited.complete();
    }),
  ];
  Isolate? isolate;
  final cancellation = Timer.periodic(const Duration(milliseconds: 20), (_) {
    if (cancelled() && !answer.isCompleted) {
      answer.complete({'status': 'not_run', 'reason': 'cancelled'});
    }
  });
  final spawn = Isolate.spawn(worker, [replies.sendPort, input],
      paused: true,
      onError: errors.sendPort,
      onExit: exits.sendPort,
      errorsAreFatal: true);
  final boot = spawn.then((created) {
    isolate = created;
    if (cancelled() || clock.elapsed >= workBudget) {
      created.kill(priority: Isolate.immediate);
    } else {
      created.resume(created.pauseCapability!);
    }
  });
  Map<String, Object?> result;
  try {
    await boot.timeout(workBudget);
    final left = workBudget - clock.elapsed;
    result = left <= Duration.zero
        ? {'status': 'not_run', 'reason': 'worker_timeout'}
        : await answer.future.timeout(left,
            onTimeout: () => {'status': 'not_run', 'reason': 'worker_timeout'});
  } catch (error) {
    result = {
      'status': 'not_run',
      'reason': 'worker_boot_failure',
      'error_type': error.runtimeType.toString()
    };
  } finally {
    cancellation.cancel();
  }
  isolate?.kill(priority: Isolate.immediate);
  // A late spawn stays paused and is killed on arrival; never run work after
  // the deadline. Missing exit acknowledgement must remain unconfirmed.
  if (isolate == null) {
    spawn.then<void>((created) => created.kill(priority: Isolate.immediate),
        onError: (Object ignoredError, StackTrace ignoredStack) {});
  }
  final cleanupLeft = total - clock.elapsed;
  try {
    await exited.future
        .timeout(cleanupLeft > Duration.zero ? cleanupLeft : Duration.zero);
    result['worker_cleanup'] = 'confirmed';
  } catch (_) {
    result['worker_cleanup'] = 'unconfirmed';
  }
  for (final subscription in subscriptions) {
    await subscription.cancel();
  }
  replies.close();
  errors.close();
  exits.close();
  result['worker_elapsed_ms'] = clock.elapsedMilliseconds;
  if (cancelled()) {
    return {
      'status': 'not_run',
      'reason': 'cancelled',
      'worker_cleanup': result['worker_cleanup'],
      'worker_elapsed_ms': result['worker_elapsed_ms']
    };
  }
  return result;
}
