import 'network_exception.dart';

/// Normalize business errors before response caching and model parsing.
void checkDanmakuResponse(dynamic data) {
  if (data is! Map || data['success'] != false) return;
  final code = int.tryParse('${data['errorCode']}');
  final message = data['errorMessage'] is String
      ? (data['errorMessage'] as String).trim()
      : '';
  throw NetworkException(
    type: NetworkExceptionType.badResponse,
    statusCode: code,
    message: code == 429
        ? '弹幕服务暂时限制请求，请稍后再试，避免连续重试'
        : '弹幕服务返回错误${code == null ? '' : ' ($code)'}${message.isEmpty ? '' : ': ${message.substring(0, message.length.clamp(0, 200))}'}',
  );
}
