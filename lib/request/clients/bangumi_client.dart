import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_error_mapper.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/bangumi_mirror_credentials.dart';
import 'package:kazumi/utils/crypto.dart';

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
    try {
      final usePublicSearchMirror = _usePublicSearchMirrorWithoutCredentials(
        url,
        requiresAuth: requiresAuth,
      );
      final response = await DioFactory.apiDio.post(
        usePublicSearchMirror
            ? Uri.parse(ApiEndpoints.bangumiSearchMirrorDomain)
                .replace(
                  path: Uri.parse(url).path,
                  query: Uri.parse(url).query,
                )
                .toString()
            : url,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          extra: usePublicSearchMirror
              ? {DioFactory.bypassBangumiMirrorExtra: true}
              : null,
          headers: _headers(
            requiresAuth: requiresAuth,
            url: url,
            method: 'POST',
            data: data,
            signMirrorRequest: !usePublicSearchMirror,
            includeSyncToken: !usePublicSearchMirror,
          ),
        ),
        cancelToken: cancelToken,
      );
      return response.data;
    } on DioException catch (e) {
      throw await NetworkErrorMapper.mapException(e);
    }
  }

  bool _usePublicSearchMirrorWithoutCredentials(
    String url, {
    required bool requiresAuth,
  }) {
    // Fork builds may lack the Kazumi mirror's CI-only signing credentials.
    // Keep public searches accelerated without sending account tokens to the
    // anonymous mirror. Other endpoints retain their existing routes.
    if (requiresAuth ||
        !GStorage.getSetting(SettingsKeys.enableBangumiProxy) ||
        ((bangumiMirrorCredentials['id']?.trim().isNotEmpty ?? false) &&
            (bangumiMirrorCredentials['value']?.trim().isNotEmpty ?? false))) {
      return false;
    }
    final uri = Uri.parse(url);
    final official = Uri.parse(ApiEndpoints.bangumiAPIDomain);
    return uri.scheme == official.scheme &&
        uri.host == official.host &&
        uri.port == official.port &&
        uri.userInfo.isEmpty &&
        uri.path == '/v0/search/subjects';
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
