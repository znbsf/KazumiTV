import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/widget/tv_artwork.dart';
import 'package:kazumi/pages/player/tv_playback_info.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

import 'support/tv_focus_fixtures.dart';

void main() {
  final catalogs = {
    'P1': {
      'medium': 'https://lain.bgm.tv/r/200/pic/cover/l/p1.jpg',
      'common': 'https://lain.bgm.tv/r/400/pic/cover/l/p1.jpg',
      'large': 'https://lain.bgm.tv/pic/cover/l/p1.jpg',
    },
    'v0': {
      'medium': 'https://api.bgm.tv/v0/subjects/1/image?type=medium',
      'common': 'https://api.bgm.tv/v0/subjects/1/image?type=common',
      'large': 'https://api.bgm.tv/v0/subjects/1/image?type=large',
    },
    'trending': {
      'medium': 'https://lain.bangumi.lat/r/800/pic/cover/l/trending.jpg',
      'common': 'https://lain.bangumi.lat/r/800/pic/cover/l/trending.jpg',
      'large': 'https://lain.bangumi.lat/pic/cover/l/trending.jpg',
    },
  };

  test('existing r/400 poster cache key is byte identical', () {
    const url = 'https://lain.bgm.tv/r/400/pic/cover/l/p1.jpg?q=%2f#frame';
    expect(NetworkImgLayer.tvListCoverUrl({'common': url}), url);
  });

  for (final entry in catalogs.entries) {
    test('${entry.key} uses the three TV tiers without mutating images', () {
      final images = Map<String, String>.of(entry.value);
      final before = Map<String, String>.of(images);
      final isApi = entry.key == 'v0';
      final host = entry.key == 'trending' ? 'lain.bangumi.lat' : 'lain.bgm.tv';
      final file = entry.key == 'P1' ? 'p1' : 'trending';
      expect(
        NetworkImgLayer.tvListCoverUrl(images, thumbnail: true),
        isApi
            ? '${images['medium']}&w=200'
            : 'https://$host/r/200/pic/cover/l/$file.jpg',
      );
      expect(
        NetworkImgLayer.tvListCoverUrl(images),
        isApi
            ? '${images['common']}&w=400'
            : 'https://$host/r/400/pic/cover/l/$file.jpg',
      );
      expect(
        NetworkImgLayer.tvDetailCoverUrl(images),
        isApi
            ? '${images['large']}&w=800'
            : 'https://$host/r/800/pic/cover/l/$file.jpg',
      );
      expect(NetworkImgLayer.tvDetailCoverUrl({'medium': images['medium']!}),
          NetworkImgLayer.tvListCoverUrl({'medium': images['medium']!}));
      expect(images, before);
    });

    for (final thumbnail in [true, false]) {
      testWidgets(
          '${entry.key} ${thumbnail ? 'thumbnail' : 'poster'} frame is the instant detail placeholder',
          (tester) async {
        TvMode.setEnabledForTesting(true);
        tester.view.devicePixelRatio = 2;
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          TvMode.setEnabledForTesting(false);
          NetworkImgLayer.clearTvCoverMemory();
          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();
        });
        final images = Map<String, String>.of(entry.value);
        final before = Map<String, String>.of(images);
        final listUrl =
            NetworkImgLayer.tvListCoverUrl(images, thumbnail: thumbnail);
        final detailUrl = NetworkImgLayer.tvDetailCoverUrl(images);
        final logicalWidth = thumbnail ? 50.0 : 163.0;
        final physicalWidth = (logicalWidth * 2).toInt();
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.red, BlendMode.src);
        final picture = recorder.endRecording();
        final small =
            picture.toImageSync(physicalWidth, physicalWidth * 3 ~/ 2);
        picture.dispose();
        (await _pending(listUrl, physicalWidth))
            .complete(ImageInfo(image: small));
        final detailReady = await _pending(detailUrl, 316);
        await tester.pumpWidget(_app(NetworkImgLayer(
          src: listUrl,
          width: logicalWidth,
          height: logicalWidth * 1.5,
          fadeInDuration: Duration.zero,
        )));
        await tester.pumpAndSettle();
        final frame = find.byWidgetPredicate((widget) =>
            widget is RawImage && widget.image?.isCloneOf(small) == true);
        expect(frame, findsOneWidget);
        final initial = NetworkImgLayer.tvInitialCoverUrl(images);
        expect(initial, listUrl);
        expect(
            TvPlaybackInfoData.fromPlayback(
              title: 'Work',
              fallbackTitle: '',
              sourceName: '',
              images: images,
              roads: [],
              roadIndex: 0,
              episodeIndex: 1,
            ).coverUrl,
            listUrl);
        await tester.pumpWidget(_app(NetworkImgLayer(
          key: const ValueKey('detail'),
          src: detailUrl,
          placeholderSrc: initial,
          width: 158,
          height: 237,
        )));
        await tester.pump(const Duration(seconds: 1));
        expect(detailReady.isCompleted, isFalse);
        expect(frame, findsOneWidget);
        expect(find.byType(Image), findsNothing);
        expect(images, before);
        final detailRecorder = ui.PictureRecorder();
        Canvas(detailRecorder).drawColor(Colors.blue, BlendMode.src);
        final detailPicture = detailRecorder.endRecording();
        final large = detailPicture.toImageSync(316, 474);
        detailPicture.dispose();
        detailReady.complete(ImageInfo(image: large));
        await tester.pumpAndSettle();
        expect(frame, findsNothing);
        expect(
            find.byWidgetPredicate((widget) =>
                widget is RawImage && widget.image?.isCloneOf(large) == true),
            findsOneWidget);
        expect(NetworkImgLayer.tvInitialCoverUrl(images), detailUrl,
            reason: 'the most recently displayed tier wins, including detail');
        expect(tester.takeException(), isNull);
      });
    }
  }

  test('TV thumbnail and original use distinct catalog URLs without mutation',
      () {
    final images = {
      'medium': 'https://fixture.invalid/poster.png',
      'common': 'https://fixture.invalid/common.png',
      'large': 'https://fixture.invalid/original.png',
    };
    final original = Map<String, String>.of(images);
    expect(NetworkImgLayer.tvListCoverUrl(images), images['common']);
    expect(NetworkImgLayer.tvListCoverUrl(images, thumbnail: true),
        images['medium']);
    expect(NetworkImgLayer.tvDetailCoverUrl(images), images['large']);
    expect(images, original);
  });

  test(
      'blank thumbnails fall back to common then original; missing large keeps thumbnail',
      () {
    expect(
        NetworkImgLayer.tvListCoverUrl({
          'medium': '  ',
          'common': 'common',
          'large': 'original',
        }),
        'common');
    expect(
        NetworkImgLayer.tvListCoverUrl({
          'medium': '',
          'common': '',
          'large': 'original',
        }),
        'original');
    expect(
        NetworkImgLayer.tvDetailCoverUrl({
          'medium': 'thumbnail',
          'large': '',
        }),
        'thumbnail');
    expect(NetworkImgLayer.tvListCoverUrl({}), '');
    expect(NetworkImgLayer.tvDetailCoverUrl({}), '');
  });

  test(
      'same Dart work notifies backdrop when Home thumbnail becomes detail original',
      () {
    final controller = TvArtworkController();
    addTearDown(controller.dispose);
    final item = focusItem(1)
      ..images = {
        'medium': 'https://fixture.invalid/poster.png',
        'common': 'https://fixture.invalid/common.png',
        'large': 'https://fixture.invalid/original.png',
      };
    var selections = 0;
    controller.addListener(() => selections++);
    controller.select(item,
        imageUrl: NetworkImgLayer.tvListCoverUrl(item.images));
    expect(controller.value, same(item));
    expect(controller.imageUrl, item.images['common']);
    controller.select(item);
    expect(controller.value, same(item));
    expect(controller.imageUrl, item.images['large']);
    expect(selections, 2);
    controller.select(item);
    expect(selections, 2);
    controller.select(null);
    expect(controller.value, isNull);
    expect(controller.imageUrl, '');
  });
}

Widget _app(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

Future<Completer<ImageInfo>> _pending(String url, int width) async {
  final provider =
      ResizeImage.resizeIfNeeded(width, null, CachedNetworkImageProvider(url));
  final key = await provider.obtainKey(ImageConfiguration.empty);
  final ready = Completer<ImageInfo>();
  PaintingBinding.instance.imageCache
      .putIfAbsent(key, () => OneFrameImageStreamCompleter(ready.future));
  return ready;
}
