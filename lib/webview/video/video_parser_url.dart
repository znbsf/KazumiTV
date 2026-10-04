import 'package:kazumi/utils/media.dart';

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
