import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/webview/video/video_parser_url.dart';

void main() {
  test('explicit player URL decodes once and preserves signed query bytes', () {
    const page = 'https://nested.test/play/3.html?sign=a%2Fb%26c&time=123';
    final player =
        Uri.https('player.test', '/player.php', {'url': page}).toString();
    expect(nestedVideoPageUrl(player, fromPlayerQuery: true), page);
    expect(nestedVideoPageUrl(page), page);
  });

  test('does not crawl ordinary iframe links or ambiguous query parameters',
      () {
    for (final url in [
      'https://site.test/iframe.html',
      'https://site.test/player?next=https://nested.test/page.html',
      'https://site.test/player?url=https://a.test/a.html&url=https://b.test/b.html',
      'https://site.test/player?url=%',
      'https://doubleclick.test/player?url=https://nested.test/page.html',
    ]) {
      expect(nestedVideoPageUrl(url, fromPlayerQuery: true), isNull);
    }
  });

  test('rejects media, ads, credentials and non-network schemes', () {
    for (final url in [
      'https://cdn.test/3.mp4',
      'https://cdn.test/3.m3u8',
      'https://site.test/prestrain.html',
      'https://googleads.test/ad.html',
      'https://name:secret@site.test/page.html',
      'javascript:alert(1)',
      'file:///page.html',
      'blob:https://site.test/id',
      '/relative.html',
      'https://site.test/no-extension',
    ]) {
      expect(nestedVideoPageUrl(url), isNull);
    }
  });
}
