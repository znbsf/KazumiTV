import 'package:kazumi/utils/media.dart';

/// A page-shaped URL explicitly supplied as a video source, never an arbitrary
/// link/iframe destination. Following it is a service-level, one-hop fallback.
String? nestedVideoPageUrl(String source, {bool fromPlayerQuery = false}) {
  try {
    if (!isVideoParserNetworkUrl(source) || isVideoParserAdUrl(source)) {
      return null;
    }
    var candidate = source;
    if (fromPlayerQuery) {
      final values = Uri.parse(source).queryParametersAll['url'];
      if (values == null || values.length != 1) return null;
      candidate = values.single;
    }
    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        !isVideoParserNetworkUrl(candidate) ||
        isVideoParserAdUrl(candidate) ||
        uri.userInfo.isNotEmpty ||
        candidate.length > 8192) {
      return null;
    }
    final path = uri.path.toLowerCase();
    if (!path.endsWith('.html') && !path.endsWith('.htm')) return null;
    return candidate;
  } on FormatException {
    return null;
  }
}

/// Read only the public media URL embedded in an iframe's query. Preserve
/// signed query bytes; decodeVideoSource adds an outer encodeFull layer.
String? embeddedVideoParserUrl(String source) {
  if (!isVideoParserNetworkUrl(source) || isVideoParserAdUrl(source)) {
    return null;
  }
  try {
    final encoded = Uri.encodeFull(source);
    final extracted = decodeVideoSource(encoded);
    if (extracted == encoded) return null;
    final decoded = Uri.parse(Uri.decodeFull(extracted)).toString();
    if (!isVideoParserNetworkUrl(decoded) || isVideoParserAdUrl(decoded)) {
      return null;
    }
    final path = Uri.parse(decoded).path.toLowerCase();
    if (!path.endsWith('.m3u8') && !path.endsWith('.mp4')) return null;
    return decoded;
  } on FormatException {
    return null;
  }
}

bool isVideoParserNetworkUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

bool isVideoParserAdUrl(String url) {
  final lower = url.toLowerCase();
  return lower.contains('googleads') ||
      lower.contains('googlesyndication') ||
      lower.contains('adtrafficquality') ||
      lower.contains('doubleclick') ||
      lower.contains('prestrain.html') ||
      lower.contains('prestrain%2ehtml');
}
