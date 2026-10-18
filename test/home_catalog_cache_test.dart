import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/services/storage/home_catalog_cache.dart';

BangumiItem item(int id) => BangumiItem.fromJson({
      'id': id,
      'name': 'Title $id',
      'rating': {'rank': 1, 'score': 7.0, 'total': 2},
      'images': {
        'large': 'https://example.com/cover.jpg',
        'small': 'https://example.com/private?token=secret',
      },
    });
void main() {
  late Directory dir;
  late HomeCatalogCache cache;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('home_cache_test_');
    cache = HomeCatalogCache(directory: dir);
  });
  tearDown(() async => dir.delete(recursive: true));
  test('first launch has no cached data', () async {
    expect(await cache.read(false), isNull);
  });
  test(
      'offline snapshot survives restart, strips signed URLs, separates providers',
      () async {
    await cache.write(false, [item(1)], DateTime.now());
    final restored = await HomeCatalogCache(directory: dir).read(false);
    expect(restored!.items.single.id, 1);
    expect(restored.items.single.images, {
      'large': 'https://example.com/cover.jpg',
    });
    expect(restored.stale, false);
    expect(await cache.read(true), isNull);
  });
  test(
    'new data replaces old snapshot and empty responses preserve it',
    () async {
      await cache.write(false, [item(1)], DateTime.now());
      await cache.write(false, [item(2)], DateTime.now());
      await cache.write(false, [], DateTime.now());
      expect((await cache.read(false))!.items.single.id, 2);
    },
  );
  test('capacity bounded to 96 items', () async {
    await cache.write(
      false,
      List.generate(200, (i) => item(i + 1)),
      DateTime.now(),
    );
    expect((await cache.read(false))!.items.length, 96);
  });
  test(
    'stale content remains available for offline use until retention expires',
    () async {
      await cache.write(
          false,
          [
            item(1),
          ],
          DateTime.now().subtract(const Duration(days: 1)));
      expect((await cache.read(false))!.stale, true);
      await cache.write(
          false,
          [
            item(1),
          ],
          DateTime.now().subtract(const Duration(days: 31)));
      expect(await cache.read(false), isNull);
    },
  );
  test(
    'corrupt and incompatible schemas are discarded and can recover',
    () async {
      final file = File('${dir.path}/home-catalog-direct.json');
      for (final raw in [
        'broken',
        jsonEncode({'version': 0}),
        jsonEncode({'version': 999}),
      ]) {
        await file.writeAsString(raw);
        expect(await cache.read(false), isNull);
        expect(await file.exists(), false);
      }
      await cache.write(false, [item(3)], DateTime.now());
      expect((await cache.read(false))!.items.single.id, 3);
    },
  );
  test('oversized persisted input is discarded before decoding', () async {
    await File('${dir.path}/home-catalog-direct.json')
        .writeAsString('x' * (HomeCatalogCache.maxBytes + 1));
    expect(await cache.read(false), isNull);
  });
}
