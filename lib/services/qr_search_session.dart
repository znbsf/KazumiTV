import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Ephemeral local-only input endpoint. No persistent storage or relay.
class QrSearchSession {
  QrSearchSession(
      {required this.onQuery,
      this.onClosed,
      this.lifetime = const Duration(minutes: 3)});
  final void Function(String) onQuery;
  final void Function()? onClosed;
  final Duration lifetime;
  static const maxLength = 120;
  HttpServer? _server;
  Timer? _timer;
  bool _closed = false;
  bool _accepted = false;
  final String token = List.generate(24, (_) => Random.secure().nextInt(256))
      .map((v) => v.toRadixString(16).padLeft(2, '0'))
      .join();
  Uri? uri;

  Future<Uri> start({InternetAddress? address}) async {
    if (_closed || _server != null) throw StateError('Session already used');
    var selected = address;
    if (selected == null) {
      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final interface in interfaces) {
        for (final candidate in interface.addresses) {
          final b = candidate.rawAddress;
          if (b[0] == 10 ||
              (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
              (b[0] == 192 && b[1] == 168)) {
            selected = candidate;
            break;
          }
        }
        if (selected != null) break;
      }
    }
    if (selected == null) throw StateError('未找到局域网地址，请连接 Wi-Fi 或网线');
    final server = await HttpServer.bind(selected, 0);
    if (_closed) {
      await server.close(force: true);
      throw StateError('Session closed');
    }
    _server = server;
    uri = Uri(
        scheme: 'http',
        host: selected.address,
        port: server.port,
        path: '/$token');
    _timer = Timer(lifetime, close);
    server.listen(_handle);
    return uri!;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    StreamSubscription<List<int>>? bodySubscription;
    Timer? bodyTimer;
    response.persistentConnection = false;
    response.headers.set('Cache-Control', 'no-store');
    response.headers.set('Referrer-Policy', 'same-origin');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.headers.set('Content-Security-Policy',
        "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'");
    try {
      if (_closed || request.uri.path != '/$token') {
        response.statusCode = 404;
      } else if (request.method == 'GET') {
        response.headers.contentType = ContentType.html;
        response.write(
            '''<!doctype html><html lang="zh"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>KazumiTV 搜索</title><body style="font:20px sans-serif;padding:24px"><h1>电视搜索</h1><p>仅本次会话有效。提交后请查看电视。</p><form method="post"><label>番剧关键词 <input name="q" maxlength="120" required autofocus></label><button>发送到电视</button></form></body></html>''');
      } else if (request.method == 'POST') {
        final origin = request.headers.value('origin');
        if (origin != null && origin != uri!.origin) {
          response.statusCode = 403;
        } else if (_accepted) {
          response.statusCode = 409;
          response.write('Already submitted');
        } else {
          final bytes = <int>[];
          final body = Completer<void>();
          void reject(Object error) {
            if (body.isCompleted) return;
            bodySubscription?.pause();
            body.completeError(error);
          }

          bodyTimer = Timer(const Duration(seconds: 5),
              () => reject(TimeoutException('Input deadline')));
          bodySubscription = request.listen((chunk) {
            if (bytes.length + chunk.length > 2048) {
              reject(const FormatException('Input too large'));
            } else {
              bytes.addAll(chunk);
            }
          }, onDone: () {
            if (!body.isCompleted) body.complete();
          }, onError: reject);
          await body.future;
          bodyTimer.cancel();
          final query =
              Uri.splitQueryString(utf8.decode(bytes))['q']?.trim() ?? '';
          if (query.isEmpty ||
              query.runes.length > maxLength ||
              query.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
            throw const FormatException('Invalid keyword');
          }
          if (_closed) {
            response.statusCode = 410;
          } else if (_accepted) {
            response.statusCode = 409;
          } else {
            _accepted = true;
            response.headers.contentType = ContentType.text;
            response.write('已发送，请查看电视。可以关闭此页。');
            onQuery(query);
          }
        }
      } else {
        response.statusCode = 405;
      }
    } on Object {
      try {
        response.statusCode = 400;
        response.write('输入无效或请求超时，请返回后重试（最多120字）。');
      } on Object {/* Session may have closed during an upload. */}
    } finally {
      bodyTimer?.cancel();
      try {
        await response.close();
      } on Object {/* Client or session closed. */}
      await bodySubscription?.cancel();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    await _server?.close(force: true);
    onClosed?.call();
  }
}
