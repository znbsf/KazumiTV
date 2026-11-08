abstract final class BangumiImageUrlRewriter {
  static const thumbnailWidth = 200;
  static const posterWidth = 400;
  static const detailWidth = 800;

  static const _apiImageKinds = {'subjects', 'characters', 'persons'};

  /// Bound known cover sources without enlarging an already smaller rendition.
  static String sized(String url, int width) {
    final uri = Uri.tryParse(url);
    if (uri == null || !_isHttp(uri)) return url;
    if (uri.host == 'lain.bgm.tv' || uri.host == 'lain.bangumi.lat') {
      if (uri.path.startsWith('/pic/cover/')) {
        return uri.replace(path: '/r/$width${uri.path}').toString();
      }
      final rendition =
          RegExp(r'^/r/(\d+)(/pic/cover/.*)$').firstMatch(uri.path);
      if (rendition != null && (int.tryParse(rendition[1]!) ?? 0) > width) {
        return uri.replace(path: '/r/$width${rendition[2]}').toString();
      }
    } else if (_isApiImage(uri)) {
      return uri.replace(queryParameters: {
        ...uri.queryParametersAll,
        'w': '$width',
      }).toString();
    }
    return url;
  }

  static String rewrite(String url, {required bool enabled}) {
    if (!enabled) return url;

    final uri = Uri.tryParse(url);
    if (uri == null || !_isHttp(uri) || !_isMirrorable(uri)) return url;

    final width = _isApiImage(uri) ? uri.queryParameters['w'] : null;
    final source = width == null
        ? uri
        : uri.replace(
            queryParameters: {...uri.queryParametersAll}..remove('w'));
    final sourceUrl =
        source.host + source.path + (source.hasQuery ? '?${source.query}' : '');
    return Uri.https('wsrv.nl', '/', {
      'url': sourceUrl,
      if (width != null) 'w': width,
      if (width != null) 'we': '',
      if (uri.path.toLowerCase().endsWith('.gif')) 'n': '-1',
    }).toString();
  }

  static bool _isHttp(Uri uri) => uri.scheme == 'http' || uri.scheme == 'https';

  static bool _isMirrorable(Uri uri) =>
      uri.host == 'lain.bgm.tv' || _isApiImage(uri);

  static bool _isApiImage(Uri uri) {
    if (uri.host != 'api.bgm.tv') return false;

    final segments = uri.pathSegments;
    if (segments.length != 4 || segments[0] != 'v0' || segments[3] != 'image') {
      return false;
    }
    final id = int.tryParse(segments[2]);
    return _apiImageKinds.contains(segments[1]) && id != null && id > 0;
  }
}
