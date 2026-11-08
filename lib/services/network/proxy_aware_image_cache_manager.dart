import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/network/bangumi_image_url_rewriter.dart';
import 'package:kazumi/services/network/proxy_utils.dart';
import 'package:kazumi/services/network/system_proxy_service.dart';
import 'package:kazumi/services/storage/storage.dart';

class ProxyAwareImageCacheManager extends CacheManager with ImageCacheManager {
  static final ProxyAwareImageCacheManager instance =
      ProxyAwareImageCacheManager._();

  @visibleForTesting
  static FileService createFileServiceForTesting({Duration? stallTimeout}) =>
      _ProxyAwareImageFileService(
        stallTimeout: stallTimeout ?? _ProxyAwareImageFileService._stallTimeout,
      );

  ProxyAwareImageCacheManager._()
      : super(
          Config(
            DefaultCacheManager.key,
            fileService: _ProxyAwareImageFileService(),
          ),
        );
}

class _ProxyAwareImageFileService extends FileService {
  _ProxyAwareImageFileService({Duration stallTimeout = _stallTimeout})
      : _timeout = stallTimeout;

  static const _stallTimeout = Duration(seconds: 20);
  final Duration _timeout;
  HttpClient? _client;
  bool? _proxyEnabled;
  (String, int)? _proxy;

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final client = _httpClient();
    final request = await client.getUrl(Uri.parse(
      BangumiImageUrlRewriter.rewrite(
        url,
        enabled: GStorage.getSetting(SettingsKeys.enableBangumiProxy),
      ),
    ));
    headers?.forEach(request.headers.set);
    final response = await request.close().timeout(_timeout, onTimeout: () {
      final error =
          TimeoutException('Image response headers stalled', _timeout);
      request.abort(error);
      throw error;
    });
    // WebHelper only reads bodies for 200/202. In particular its error and
    // 304 paths never subscribe to content, so release those slots here.
    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.accepted) {
      await _drainOnCancel(request, response).drain<void>();
      return _ProxyAwareImageFileServiceResponse(
          response, const Stream.empty());
    }
    return _ProxyAwareImageFileServiceResponse(
        response, _drainOnCancel(request, response));
  }

  HttpClient _httpClient() {
    final enabled = GStorage.getSetting<bool>(SettingsKeys.proxyEnable);
    final proxy = enabled ? _currentProxy() : null;
    if (_client != null && enabled == _proxyEnabled && proxy == _proxy) {
      return _client!;
    }

    final previous = _client;
    final client = HttpClient()
      ..maxConnectionsPerHost = 6
      ..connectionTimeout = const Duration(seconds: 12);
    if (proxy != null) {
      client.findProxy = (_) => 'PROXY ${proxy.$1}:${proxy.$2}';
    } else if (Platform.isWindows) {
      // System and manual proxy routes both retain certificate verification.
      client.findProxy = SystemProxyService.findProxy;
    }
    _client = client;
    _proxyEnabled = enabled;
    _proxy = proxy;
    // Retire idle connections but allow existing downloads to finish.
    previous?.close();
    return client;
  }

  (String, int)? _currentProxy() {
    final String proxyUrl = GStorage.getSetting(SettingsKeys.proxyUrl);
    final parsed = ProxyUtils.parseProxyUrl(proxyUrl);
    if (parsed == null) {
      KazumiLogger().w('Proxy: 图片缓存代理地址格式错误或为空');
    }
    return parsed;
  }

  /// Continue consuming the HTTP body when a cache writer cancels midway.
  /// Discard remaining chunks without closing the pool or buffering the body.
  Stream<List<int>> _drainOnCancel(
      HttpClientRequest request, HttpClientResponse response) {
    late StreamController<List<int>> controller;
    late StreamSubscription<List<int>> subscription;
    final finished = Completer<void>();
    Timer? timer;
    var discarding = false;

    void finish() {
      timer?.cancel();
      if (!finished.isCompleted) {
        finished.complete();
        unawaited(controller.close());
      }
    }

    void resetTimer() {
      timer?.cancel();
      if (finished.isCompleted) return;
      timer = Timer(_timeout, () {
        final error = TimeoutException('Image response body stalled', _timeout);
        request.abort(error);
        // Dart's abort can be a no-op once headers have arrived. Cancelling
        // the HTTP subscription also closes that response's connection.
        unawaited(subscription.cancel());
        if (!discarding) controller.addError(error);
        finish();
      });
    }

    controller = StreamController<List<int>>(
      onListen: () {
        resetTimer();
        subscription = response.listen(
          (chunk) {
            resetTimer();
            if (!discarding) controller.add(chunk);
          },
          onError: (Object error, StackTrace stack) {
            if (!discarding) controller.addError(error, stack);
            finish();
          },
          onDone: finish,
          cancelOnError: true,
        );
      },
      onPause: () {
        timer?.cancel();
        subscription.pause();
      },
      onResume: () {
        resetTimer();
        subscription.resume();
      },
      onCancel: () async {
        if (!finished.isCompleted) {
          discarding = true;
          resetTimer();
          subscription.resume();
        }
        await finished.future;
      },
    );
    return controller.stream;
  }
}

class _ProxyAwareImageFileServiceResponse implements FileServiceResponse {
  _ProxyAwareImageFileServiceResponse(this._response, this.content);

  final HttpClientResponse _response;
  final DateTime _receivedTime = DateTime.now();

  @override
  final Stream<List<int>> content;

  @override
  int? get contentLength =>
      _response.contentLength >= 0 ? _response.contentLength : null;

  @override
  String? get eTag => _response.headers.value(HttpHeaders.etagHeader);

  @override
  String get fileExtension {
    return switch (_response.headers.contentType?.mimeType.toLowerCase()) {
      'image/jpeg' => '.jpg',
      'image/png' => '.png',
      'image/gif' => '.gif',
      'image/webp' => '.webp',
      'image/bmp' => '.bmp',
      'image/x-icon' || 'image/vnd.microsoft.icon' => '.ico',
      'image/avif' => '.avif',
      'image/svg+xml' => '.svg',
      _ => '',
    };
  }

  @override
  int get statusCode => _response.statusCode;

  @override
  DateTime get validTill {
    var ageDuration = const Duration(days: 7);
    final controlHeader =
        _response.headers.value(HttpHeaders.cacheControlHeader);
    if (controlHeader == null) {
      return _receivedTime.add(ageDuration);
    }

    final controlSettings = controlHeader.split(',');
    for (final setting in controlSettings) {
      final sanitizedSetting = setting.trim().toLowerCase();
      if (sanitizedSetting == 'no-cache') {
        ageDuration = Duration.zero;
      }
      if (sanitizedSetting.startsWith('max-age=')) {
        final validSeconds =
            int.tryParse(sanitizedSetting.split('=').last) ?? 0;
        if (validSeconds > 0) {
          ageDuration = Duration(seconds: validSeconds);
        }
      }
    }

    return _receivedTime.add(ageDuration);
  }
}
