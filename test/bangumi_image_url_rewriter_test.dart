import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/network/bangumi_image_url_rewriter.dart';

void main() {
  group('BangumiImageUrlRewriter', () {
    group('sized', () {
      for (final host in ['lain.bgm.tv', 'lain.bangumi.lat']) {
        test('$host bounds original covers, including GIFs', () {
          for (final extension in ['jpg', 'gif']) {
            final url = 'https://$host/pic/cover/l/cover.$extension?q=1#frame';
            expect(BangumiImageUrlRewriter.sized(url, 200),
                'https://$host/r/200/pic/cover/l/cover.$extension?q=1#frame');
          }
        });
        test('$host reduces larger renditions and preserves smaller bytes', () {
          expect(
            BangumiImageUrlRewriter.sized(
                'https://$host/r/1200/pic/cover/l/cover.jpg', 800),
            'https://$host/r/800/pic/cover/l/cover.jpg',
          );
          for (final rendition in [200, 400]) {
            final url =
                'https://$host/r/$rendition/pic/cover/l/cover.jpg?q=%2f#frame';
            expect(BangumiImageUrlRewriter.sized(url, 400), url);
          }
        });
      }

      test('API images retain type and other query values', () {
        for (final kind in ['subjects', 'characters', 'persons']) {
          final sized = Uri.parse(BangumiImageUrlRewriter.sized(
              'https://api.bgm.tv/v0/$kind/1/image?type=large&tag=a&tag=b&w=1200',
              800));
          expect(sized.queryParameters['type'], 'large');
          expect(sized.queryParameters['w'], '800');
          expect(sized.queryParametersAll['tag'], ['a', 'b']);
        }
      });

      test('leaves everything outside the cover boundary unchanged', () {
        for (final url in [
          '',
          'https://[invalid',
          'relative/pic/cover/file.jpg',
          'https://fixture.invalid/pic/cover/l/file.gif',
          'https://lain.bgm.tv/pic/user/l/avatar.jpg',
          'https://lain.bangumi.lat/r/800/pic/user/l/avatar.jpg',
          'https://lain.bgm.tv/r/no-size/pic/cover/l/file.jpg',
          'ftp://lain.bgm.tv/pic/cover/l/file.jpg',
          'https://api.bgm.tv/v0/subjects/0/image?type=large',
          'https://api.bgm.tv/v0/subjects/not-an-id/image?type=large',
          'https://api.bgm.tv/v0/episodes/1/image?type=large',
          'https://api.bgm.tv/v0/subjects/1',
        ]) {
          expect(BangumiImageUrlRewriter.sized(url, 400), url, reason: url);
        }
      });
    });

    test('moves API width to wsrv with no enlargement; disabled is exact', () {
      for (final kind in ['subjects', 'characters', 'persons']) {
        final url =
            'https://api.bgm.tv/v0/$kind/1/image?type=large&w=800&tag=a&tag=b';
        final rewritten =
            Uri.parse(BangumiImageUrlRewriter.rewrite(url, enabled: true));
        expect(rewritten.host, 'wsrv.nl');
        expect(rewritten.queryParameters['w'], '800');
        expect(rewritten.queryParameters.containsKey('we'), isTrue);
        final source = Uri.parse('https://${rewritten.queryParameters['url']}');
        expect(source.queryParameters.containsKey('w'), isFalse);
        expect(source.queryParameters['type'], 'large');
        expect(source.queryParametersAll['tag'], ['a', 'b']);
        expect(BangumiImageUrlRewriter.rewrite(url, enabled: false), url);
      }
    });

    test('keeps URLs unchanged when disabled', () {
      const url = 'https://api.bgm.tv/v0/subjects/590353/image?type=large';

      expect(BangumiImageUrlRewriter.rewrite(url, enabled: false), url);
    });

    test('rewrites lain images and preserves GIF animation', () {
      expect(
        BangumiImageUrlRewriter.rewrite(
          'https://lain.bgm.tv/pic/cover/l/cover.jpg',
          enabled: true,
        ),
        'https://wsrv.nl/?url=lain.bgm.tv%2Fpic%2Fcover%2Fl%2Fcover.jpg',
      );
      expect(
        BangumiImageUrlRewriter.rewrite(
          'https://lain.bgm.tv/pic/cover/l/animated.gif',
          enabled: true,
        ),
        'https://wsrv.nl/?url=lain.bgm.tv%2Fpic%2Fcover%2Fl%2Fanimated.gif&n=-1',
      );
      final sizedGif = BangumiImageUrlRewriter.sized(
          'https://lain.bgm.tv/pic/cover/l/animated.gif', 200);
      final rewritten =
          Uri.parse(BangumiImageUrlRewriter.rewrite(sizedGif, enabled: true));
      expect(rewritten.queryParameters['n'], '-1');
      expect(rewritten.queryParameters['url'],
          'lain.bgm.tv/r/200/pic/cover/l/animated.gif');
    });

    test('rewrites synthetic API image endpoints', () {
      for (final type in ['subjects', 'characters', 'persons']) {
        final source = 'https://api.bgm.tv/v0/$type/590353/image?type=large';
        expect(
          BangumiImageUrlRewriter.rewrite(source, enabled: true),
          'https://wsrv.nl/?url=api.bgm.tv%2Fv0%2F$type%2F590353%2Fimage%3Ftype%3Dlarge',
        );
      }
    });

    test('rejects URLs outside the image boundary', () {
      for (final url in [
        'ftp://lain.bgm.tv/pic/cover/l/cover.jpg',
        'https://api.bgm.tv/v0/subjects/590353',
        'https://api.bgm.tv/v0/subjects/not-an-id/image?type=large',
        'https://api.bgm.tv/v0/episodes/1/image?type=large',
        'https://example.com/v0/subjects/590353/image?type=large',
      ]) {
        expect(BangumiImageUrlRewriter.rewrite(url, enabled: true), url);
      }
    });
  });
}
