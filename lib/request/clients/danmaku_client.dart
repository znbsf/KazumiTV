import 'package:dio/dio.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_error_mapper.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/utils/dandan_credentials.dart';
import 'package:kazumi/utils/http_headers.dart';
import 'package:kazumi/utils/crypto.dart';

class DanmakuClient {
  DanmakuClient._();

  static final DanmakuClient instance = DanmakuClient._();

  Future<dynamic> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic> headers = const {},
    CancelToken? cancelToken,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final uri = Uri.parse(url);
    final requestHeaders = <String, dynamic>{
      'user-agent': getRandomUA(),
      'referer': '',
      'X-Auth': 1,
      'X-AppId': dandanCredentials['id'],
      'X-Timestamp': timestamp,
      'X-Signature': generateDandanSignature(uri.path, timestamp),
      ...headers,
    };

    try {
      final response = await DioFactory.apiDio.get(
        url,
        queryParameters: queryParameters,
        options: Options(headers: requestHeaders),
        cancelToken: cancelToken,
      );
      return response.data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        throw NetworkException(
          type: NetworkExceptionType.badResponse,
          statusCode: 429,
          message: '弹幕服务暂时限制请求，请稍后再试，避免连续重试',
          rawError: e,
          stackTrace: e.stackTrace,
        );
      }
      throw await NetworkErrorMapper.mapException(e);
    }
  }
}
