import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_config.dart';
import 'package:kazumi/webview/video/video_parser_url.dart';

/// Narrow fallback for the reproduced WebView 66 / HHJX origin-policy failure.
/// The normal WebView request runs first. No generic response scraping, script
/// replacement, cookie access, or changes to global WebView/network settings.
class LegacyPlayerCompat {
  LegacyPlayerCompat(
      {Dio? client,
      this.budget = const Duration(seconds: 8),
      this.onDiagnostic})
      : _client = client;
  final void Function(String)? onDiagnostic;
  final Dio? _client;
  final Duration budget;
  static const origin = 'https://hhjx.hhplayer.com';
  static const endpoint = '$origin/api/parse';
  String? _episode;
  Uri? _page;
  String? _userAgent;
  bool _attempted = false;
  bool _ambiguous = false;
  int _generation = 0;
  CancelToken? _cancel;

  void begin(String episode, {required bool enabled}) {
    cancel();
    final uri = Uri.tryParse(episode);
    if (enabled &&
        uri?.scheme == 'https' &&
        uri?.host == 'dmbus.cc' &&
        uri?.port == 443 &&
        uri!.userInfo.isEmpty &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty &&
        RegExp(r'^/p/\d+-\d+-\d+\.html$').hasMatch(uri.path)) {
      _episode = episode;
    }
  }

  void observePage(String url, Map<String, String>? headers) {
    if (_episode == null || _ambiguous || headers == null) return;
    final normalized = headers.map((k, v) => MapEntry(k.toLowerCase(), v));
    // Bind native iframe callbacks to this exact episode, not a retired page.
    if (normalized['referer'] != _episode) return;
    final page = Uri.tryParse(url);
    if (page == null ||
        page.scheme != 'https' ||
        page.host.isEmpty ||
        page.origin != origin ||
        page.path != '/' ||
        page.userInfo.isNotEmpty ||
        page.fragment.isNotEmpty ||
        page.queryParametersAll.length != 1) {
      return;
    }
    final values = page.queryParametersAll['url'];
    if (values == null ||
        values.length != 1 ||
        !RegExp(r'^[A-Fa-f0-9]{32,2048}$').hasMatch(values.single)) {
      return;
    }
    if (_page != null && _page != page) {
      _ambiguous = true;
      _cancel?.cancel();
      return;
    }
    _page = page;
    _userAgent = normalized['user-agent'];
  }

  Future<String?> onHttpError(String url, int? status) async {
    final page = _page;
    if (url != endpoint ||
        status != 403 ||
        page == null ||
        _ambiguous ||
        _attempted ||
        _episode == null) {
      return null;
    }
    _attempted = true;
    onDiagnostic?.call('start webview66 source adapter');
    final generation = _generation;
    final token = _cancel = CancelToken();
    final dio = _client ??
        DioFactory.createForConfig(
            NetworkConfig.fromSettings().copyWith(enableLog: false));
    final timer = Timer(budget, () => token.cancel('compat deadline'));
    try {
      final html = await _read(dio, page.toString(), token, 65536,
          headers: {if (_userAgent != null) 'User-Agent': _userAgent});
      if (token.isCancelled || generation != _generation) return null;
      final match =
          RegExp(r'window\.__HHJX_BOOTSTRAP__\s*=\s*(\{[^\r\n]{1,8192}\})\s*;')
              .firstMatch(html);
      if (match == null) return null;
      final bootstrap = jsonDecode(match.group(1)!);
      if (bootstrap is! Map ||
          bootstrap['error'] != null ||
          bootstrap['url'] != page.queryParameters['url'] ||
          bootstrap['t'] is! int ||
          bootstrap['key'] is! String ||
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(bootstrap['key'] as String) ||
          (bootstrap['act'] != null && bootstrap['act'] != 99)) {
        return null;
      }
      // These are the page's own fresh parameters, submitted only to its own
      // origin. No arbitrary API, caller-supplied Origin, or credential reuse.
      final text = await _read(dio, endpoint, token, 16384, headers: {
        if (_userAgent != null) 'User-Agent': _userAgent,
        'Origin': origin,
        'Referer': page.toString()
      }, data: {
        'url': bootstrap['url'],
        't': bootstrap['t'],
        'key': bootstrap['key'],
        'client_fallback': false,
        if (bootstrap['act'] == 99) 'act': 99
      });
      if (token.isCancelled || generation != _generation) return null;
      final result = jsonDecode(text);
      if (result is! Map ||
          result['code'] != 200 ||
          (result['ext'] != null && result['ext'] != '') ||
          result['url'] is! String) {
        return null;
      }
      final media = result['url'] as String;
      final uri = Uri.tryParse(media);
      if (media.length > 8192 ||
          uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          isVideoParserAdUrl(media) ||
          !RegExp(r'\.(mp4|m3u8)$', caseSensitive: false).hasMatch(uri.path)) {
        return null;
      }
      onDiagnostic?.call('resolved validated media');
      return media;
    } catch (error) {
      if (generation == _generation) {
        onDiagnostic?.call(error is DioException
            ? 'transport ${error.type.name} status=${error.response?.statusCode}'
            : 'invalid response');
      }
      return null; // Keep the existing bounded parser failure/cancel behavior.
    } finally {
      if (generation == _generation) {
        onDiagnostic?.call('finished cancelled=${token.isCancelled}');
      }
      timer.cancel();
      if (identical(_cancel, token)) _cancel = null;
      if (_client == null) dio.close(force: true);
    }
  }

  Future<String> _read(Dio dio, String url, CancelToken token, int limit,
      {Map<String, dynamic> headers = const {}, Object? data}) async {
    final response = await dio.request<ResponseBody>(url,
        data: data,
        cancelToken: token,
        options: Options(
            method: data == null ? 'GET' : 'POST',
            headers: headers,
            contentType: data == null ? null : 'application/json',
            responseType: ResponseType.stream,
            followRedirects: false,
            validateStatus: (status) => status == 200));
    final body = response.data;
    if (body == null) throw const FormatException('Empty response');
    final bytes = <int>[];
    await for (final chunk in body.stream) {
      if (token.isCancelled || bytes.length + chunk.length > limit) {
        token.cancel('compat response limit');
        throw const FormatException('Response limit');
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }

  void cancel() {
    _generation++;
    _cancel?.cancel('page retired');
    _cancel = null;
    _episode = null;
    _page = null;
    _userAgent = null;
    _attempted = false;
    _ambiguous = false;
  }
}
