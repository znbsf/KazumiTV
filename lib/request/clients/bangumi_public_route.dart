import 'package:dio/dio.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/request/core/network_exception.dart';

/// Only anonymous, read-only endpoints with a compatible public response.
/// Account endpoints and Kazumi-specific APIs must never enter this route.
class BangumiPublicRoute {
  const BangumiPublicRoute(this.official, this.mirror, this.isComments);

  final Uri official;
  final Uri mirror;
  final bool isComments;

  Uri? get secondarySearchMirror =>
      official.host == Uri.parse(ApiEndpoints.bangumiAPIDomain).host &&
              official.path == '/v0/search/subjects'
          ? Uri.parse(ApiEndpoints.bangumiSearchFallbackMirrorDomain).replace(
              path: official.path,
              query: official.hasQuery ? official.query : null)
          : null;

  static BangumiPublicRoute? match(String url, String method) {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' || uri.port != 443 || uri.userInfo.isNotEmpty) {
      return null;
    }
    final next = uri.host == Uri.parse(ApiEndpoints.bangumiAPINextDomain).host;
    final api = uri.host == Uri.parse(ApiEndpoints.bangumiAPIDomain).host;
    if (!next && !api) return null;
    final comments =
        RegExp(r'^/p1/(subjects|episodes|characters)/[1-9]\d*/comments$')
            .hasMatch(uri.path);
    final allowed = method == 'POST'
        ? api && uri.path == '/v0/search/subjects'
        : method == 'GET' &&
            (next &&
                    (comments ||
                        RegExp(r'^/p1/(subjects|characters)/[1-9]\d*$')
                            .hasMatch(uri.path) ||
                        uri.path == '/p1/calendar' ||
                        uri.path == '/p1/trending/subjects') ||
                api &&
                    (RegExp(r'^/v0/subjects/[1-9]\d*(/(subjects|characters|persons))?$')
                            .hasMatch(uri.path) ||
                        uri.path == '/v0/episodes'));
    if (!allowed) return null;
    final mirror = Uri.parse(next
            ? ApiEndpoints.bangumiNextMirrorDomain
            : ApiEndpoints.bangumiSearchMirrorDomain)
        .replace(path: uri.path, query: uri.hasQuery ? uri.query : null);
    return BangumiPublicRoute(uri, mirror, comments);
  }

  static bool canRetry(Object error) {
    if (error is FormatException) return true;
    if (error is NetworkException) {
      if (error.rawError is DioException) {
        return canRetry(error.rawError!);
      }
      return false;
    }
    if (error is! DioException) return false;
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return true;
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode;
        return status == 404 ||
            (status != null && status >= 500 && status < 600);
      default:
        // Cancellation, bad certificates, authentication and throttling stay
        // visible. A fallback never disables TLS or retries account operations.
        return false;
    }
  }

  void validate(dynamic data) {
    final path = official.path;
    bool valid;
    if (path == '/p1/calendar') {
      valid = data is Map &&
          List.generate(7, (i) => '${i + 1}').every((day) => data[day] is List);
    } else if (path == '/v0/search/subjects' ||
        path == '/v0/episodes' ||
        path == '/p1/trending/subjects' ||
        path.startsWith('/p1/subjects/') && isComments) {
      valid = data is Map &&
          (data['data'] is List || data['list'] is List) &&
          (!isComments || data['total'] is num);
    } else if (isComments ||
        RegExp(r'^/v0/subjects/\d+/(subjects|characters|persons)$')
            .hasMatch(path)) {
      valid = data is List;
    } else {
      valid = data is Map && data['id'] is num;
    }
    if (!valid) throw FormatException('Invalid public Bangumi response: $path');
  }
}
