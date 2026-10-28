import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_error_mapper.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/bangumi_mirror_credentials.dart';
import 'package:kazumi/utils/crypto.dart';
import 'package:kazumi/request/clients/bangumi_public_route.dart';
import 'package:kazumi/services/logging/logger.dart';

class BangumiClient {
  BangumiClient._();

  static final BangumiClient instance = BangumiClient._();

  Future<dynamic> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = false,
    String? accessToken,
    CancelToken? cancelToken,
  }) async {
    final route = !requiresAuth &&
            accessToken == null &&
            GStorage.getSetting(SettingsKeys.enableBangumiProxy)
        ? BangumiPublicRoute.match(url, 'GET')
        : null;
    if (route != null) {
      return _publicRequest(
        route,
        'GET',
        first: route.isComments && !_hasMirrorCredentials ? route.mirror : null,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
      );
    }
    try {
      final response = await DioFactory.apiDio.get(
        url,
        queryParameters: queryParameters,
        options: Options(
          headers: _headers(
            requiresAuth: requiresAuth,
            accessToken: accessToken,
            url: url,
            method: 'GET',
          ),
        ),
        cancelToken: cancelToken,
      );
      return response.data;
    } on DioException catch (e) {
      throw await NetworkErrorMapper.mapException(e);
    }
  }

  Future<dynamic> post(
    String url, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = false,
    CancelToken? cancelToken,
  }) async {
    final route =
        !requiresAuth && GStorage.getSetting(SettingsKeys.enableBangumiProxy)
            ? BangumiPublicRoute.match(url, 'POST')
            : null;
    if (route != null) {
      return _publicRequest(
        route,
        'POST',
        first: !_hasMirrorCredentials ? route.mirror : null,
        data: data,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
      );
    }
    try {
      final response = await DioFactory.apiDio.post(
        url,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          headers: _headers(
            requiresAuth: requiresAuth,
            url: url,
            method: 'POST',
            data: data,
          ),
        ),
        cancelToken: cancelToken,
      );
      return response.data;
    } on DioException catch (e) {
      throw await NetworkErrorMapper.mapException(e);
    }
  }

  bool get _hasMirrorCredentials =>
      (bangumiMirrorCredentials['id']?.trim().isNotEmpty ?? false) &&
      (bangumiMirrorCredentials['value']?.trim().isNotEmpty ?? false);

  /// Used when a Kazumi-specific catalogue is unavailable. The payload is
  /// still public search, even in builds with Kazumi signing credentials.
  Future<dynamic> publicSearch({
    required Object data,
    required int limit,
    required int offset,
    CancelToken? cancelToken,
  }) {
    final url = ApiEndpoints.formatUrl(
      ApiEndpoints.bangumiAPIDomain + ApiEndpoints.bangumiRankSearch,
      [limit, offset],
    );
    final route = BangumiPublicRoute.match(url, 'POST')!;
    return _publicRequest(
      route,
      'POST',
      first: GStorage.getSetting(SettingsKeys.enableBangumiProxy)
          ? route.mirror
          : route.official,
      data: data,
      cancelToken: cancelToken,
    );
  }

  Future<dynamic> _publicRequest(
    BangumiPublicRoute route,
    String method, {
    Uri? first,
    Object? data,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    // null denotes the existing Kazumi interceptor route. Distinct explicit
    // URLs bypass that interceptor, so the final official attempt is direct.
    final attempts = <Uri?>[first];
    if (first != route.mirror && first != route.official) {
      attempts.add(route.mirror);
    }
    if (first != route.official) {
      final secondary = route.secondarySearchMirror;
      if (secondary != null) attempts.add(secondary);
      attempts.add(route.official);
    }
    for (var i = 0; i < attempts.length; i++) {
      final target = attempts[i];
      try {
        if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
        final response = await DioFactory.apiDio.request(
          (target ?? route.official).toString(),
          data: data,
          queryParameters: queryParameters,
          cancelToken: cancelToken,
          options: Options(
            method: method,
            extra: target == null
                ? null
                : {DioFactory.bypassBangumiMirrorExtra: true},
            headers: _headers(
              requiresAuth: false,
              url: route.official.toString(),
              method: method,
              data: data,
              includeSyncToken: false,
              signMirrorRequest: target == null,
            ),
          ),
        );
        route.validate(response.data);
        return response.data;
      } on DioException catch (e) {
        if (i == attempts.length - 1 || !BangumiPublicRoute.canRetry(e)) {
          throw await NetworkErrorMapper.mapException(e);
        }
        KazumiLogger().w('Bangumi public fallback: ${route.official.path} '
            '${e.type.name}/${e.response?.statusCode ?? "-"} -> '
            '${attempts[i + 1]!.host}');
      } on FormatException catch (e, stack) {
        if (i == attempts.length - 1) {
          throw NetworkErrorMapper.parse(e, stack);
        }
        KazumiLogger().w('Bangumi public fallback: ${route.official.path} '
            'invalid response -> ${attempts[i + 1]!.host}');
      }
    }
    throw StateError('Public Bangumi route has no attempts');
  }

  Map<String, dynamic> _headers({
    required bool requiresAuth,
    String? accessToken,
    required String url,
    required String method,
    Object? data,
    bool signMirrorRequest = true,
    bool includeSyncToken = true,
  }) {
    final headers = <String, dynamic>{...bangumiHTTPHeader};
    final bangumiSyncEnable =
        GStorage.getSetting(SettingsKeys.bangumiSyncEnable);
    final token = (accessToken ??
            GStorage.getSetting<String>(SettingsKeys.bangumiAccessToken))
        .trim();
    if ((requiresAuth || (includeSyncToken && bangumiSyncEnable)) &&
        token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (signMirrorRequest && _shouldSignProtectedMirrorRequest(url, method)) {
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final body = data == null ? '' : jsonEncode(data);
      headers['X-AppId'] = bangumiMirrorCredentials['id'];
      headers['X-Timestamp'] = timestamp;
      headers['X-Signature'] = generateBangumiMirrorSearchSignature(
        method: method,
        path: Uri.parse(url).path,
        body: body,
        timestamp: timestamp,
      );
    }
    return headers;
  }

  bool _shouldSignProtectedMirrorRequest(String url, String method) {
    final enableBangumiProxy =
        GStorage.getSetting(SettingsKeys.enableBangumiProxy);
    if (!enableBangumiProxy) {
      return false;
    }
    final path = Uri.parse(url).path;
    if (method == 'POST' && path == '/v0/search/subjects') {
      return true;
    }
    if (method != 'GET') {
      return false;
    }
    return path.startsWith('/p1/subjects/') && path.endsWith('/comments') ||
        path.startsWith('/p1/episodes/') && path.endsWith('/comments') ||
        path.startsWith('/p1/characters/') && path.endsWith('/comments');
  }
}
