import 'package:dio/dio.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_error_mapper.dart';
import 'package:kazumi/utils/http_headers.dart';

class PluginSiteClient {
  PluginSiteClient._();

  static final PluginSiteClient instance = PluginSiteClient._();

  Future<String> requestText(
    String url, {
    required String method,
    Map<String, dynamic> headers = const {},
    Map<String, dynamic> queryParameters = const {},
    Object? data,
    CancelToken? cancelToken,
  }) async {
    try {
      var target = Uri.parse(url);
      var currentHeaders = _headers(headers);
      var currentMethod = method;
      var body = data;
      for (var hop = 0; hop <= 5; hop++) {
        final response = await DioFactory.pluginDio.request<String>(
          target.toString(),
          queryParameters: hop == 0 ? queryParameters : null,
          data: body,
          options: Options(
            method: currentMethod,
            responseType: ResponseType.plain,
            headers: currentHeaders,
            followRedirects: false,
            validateStatus: (status) =>
                status != null && status >= 200 && status < 400,
          ),
          cancelToken: cancelToken,
        );
        final status = response.statusCode;
        if (![301, 302, 303, 307, 308].contains(status))
          return response.data ?? '';
        final location = response.headers.value('location');
        if (location == null || hop == 5)
          throw const FormatException('Invalid or excessive rule redirects');
        final next = response.realUri.resolve(location);
        if (!['http', 'https'].contains(next.scheme) ||
            next.userInfo.isNotEmpty) {
          throw const FormatException('Unsupported rule redirect');
        }
        if (status == 303 ||
            ((status == 301 || status == 302) && currentMethod == 'POST')) {
          currentMethod = 'GET';
          body = null;
        }
        if (next.origin != target.origin) {
          if (currentMethod != 'GET' && currentMethod != 'HEAD') {
            throw const FormatException(
                'Cross-origin rule body redirect rejected');
          }
          // Never forward manually attached credentials to another origin,
          // including subdomains, other ports or an HTTPS downgrade.
          currentHeaders = Map<String, dynamic>.from(currentHeaders)
            ..removeWhere((key, value) => {
                  'cookie',
                  'authorization',
                  'proxy-authorization',
                  'referer'
                }.contains(key.toLowerCase()));
        }
        target = next;
      }
      throw const FormatException('Excessive rule redirects');
    } on DioException catch (e) {
      throw await NetworkErrorMapper.mapException(e);
    }
  }

  Map<String, dynamic> _headers(Map<String, dynamic> headers) {
    return {
      'user-agent': getRandomUA(),
      'Accept-Language': getRandomAcceptedLanguage(),
      'Connection': 'keep-alive',
      ...headers,
    };
  }
}
