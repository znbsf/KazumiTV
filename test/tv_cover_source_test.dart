import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/widget/tv_artwork.dart';

import 'support/tv_focus_fixtures.dart';

void main() {
  test('TV thumbnail and original use distinct catalog URLs without mutation',
      () {
    final images = {
      'medium': 'https://fixture.invalid/poster.png',
      'common': 'https://fixture.invalid/common.png',
      'large': 'https://fixture.invalid/original.png',
    };
    final original = Map<String, String>.of(images);
    expect(NetworkImgLayer.tvListCoverUrl(images), images['medium']);
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
        'large': 'https://fixture.invalid/original.png',
      };
    var selections = 0;
    controller.addListener(() => selections++);
    controller.select(item,
        imageUrl: NetworkImgLayer.tvListCoverUrl(item.images));
    expect(controller.value, same(item));
    expect(controller.imageUrl, item.images['medium']);
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
