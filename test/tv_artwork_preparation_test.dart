import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/tv_artwork_preparation.dart';

Future<ui.Image> _pattern() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var y = 0; y < 120; y += 10) {
    for (var x = 0; x < 60; x += 10) {
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), y.toDouble(), 10, 10),
        Paint()
          ..color = [
            Colors.red,
            Colors.blue,
            Colors.green,
            Colors.white
          ][(x ~/ 10 + y ~/ 10) % 4],
      );
    }
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(60, 120);
  } finally {
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final dpr in [1.0, 2.0]) {
    testWidgets('async portrait pixels match old ImageFiltered at DPR $dpr',
        (tester) async {
      const logicalSize = Size(96, 64);
      tester.view.devicePixelRatio = dpr;
      tester.view.physicalSize = logicalSize * dpr;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final source = (await tester.runAsync(_pattern))!;
      final referenceKey = GlobalKey();
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: referenceKey,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: RawImage(
              image: source,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ));
      await tester.pump();
      final reference = (await tester.runAsync(() =>
          (referenceKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: dpr)))!;
      final prepared = (await tester.runAsync(() => rasterizeTvPortraitArtwork(
          source, 1, TvArtworkGeometry(logicalSize, dpr))))!;
      final expected = (await tester.runAsync(
          () => reference.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
      final actual = (await tester.runAsync(
          () => prepared.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
      expect(prepared.width, (logicalSize.width * dpr).toInt());
      expect(prepared.height, (logicalSize.height * dpr).toInt());
      expect(actual.lengthInBytes, expected.lengthInBytes);
      var largestDifference = 0;
      var differenceSum = 0;
      for (var i = 0; i < actual.lengthInBytes; ++i) {
        final difference = (actual.getUint8(i) - expected.getUint8(i)).abs();
        largestDifference =
            difference > largestDifference ? difference : largestDifference;
        differenceSum += difference;
      }
      expect(largestDifference, lessThanOrEqualTo(2));
      expect(differenceSum / actual.lengthInBytes, lessThanOrEqualTo(.25));
      await tester.pumpWidget(const SizedBox());
      prepared.dispose();
      reference.dispose();
      source.dispose();
    });
  }

  test('real raster queue keeps one active and only the latest pending work',
      () async {
    final source = await _pattern();
    final info = ImageInfo(image: source);
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final generated = <ui.Image>[];
    final inputs = <ui.Image>[];
    var active = 0;
    var maximumActive = 0;
    final preparer =
        TvArtworkPreparer(rasterizer: (image, scale, geometry) async {
      inputs.add(image);
      ++active;
      maximumActive = active > maximumActive ? active : maximumActive;
      final output = await rasterizeTvPortraitArtwork(image, scale, geometry);
      generated.add(output);
      if (generated.length == 1) {
        firstStarted.complete();
        await releaseFirst.future;
      }
      --active;
      return output;
    });
    const geometry = TvArtworkGeometry(Size(96, 64), 1);
    final a = preparer.prepare(url: 'A', source: info, geometry: geometry);
    await firstStarted.future;
    final b = preparer.prepare(url: 'B', source: info, geometry: geometry);
    final c = preparer.prepare(url: 'C', source: info, geometry: geometry);
    expect(await b, isNull);
    expect(preparer.hasActivePreparation, isTrue);
    expect(preparer.hasPendingPreparation, isTrue);
    releaseFirst.complete();
    expect(await a, isNull);
    final latest = (await c)!;
    expect(latest.key.url, 'C');
    expect(maximumActive, 1);
    expect(generated, hasLength(2),
        reason: 'B was discarded before any raster');
    expect(generated.first.debugDisposed, isTrue);
    expect(inputs.every((image) => image.debugDisposed), isTrue);
    expect(preparer.hasActivePreparation, isFalse);
    latest.dispose();
    preparer.dispose();
    info.dispose();
  });

  test('cache eviction preserves a fade owner and geometry changes reprepare',
      () async {
    final info = ImageInfo(image: await _pattern());
    var rasters = 0;
    final preparer = TvArtworkPreparer(rasterizer: (image, scale, geometry) {
      ++rasters;
      return rasterizeTvPortraitArtwork(image, scale, geometry);
    });
    const geometry = TvArtworkGeometry(Size(96, 64), 1);
    final first =
        (await preparer.prepare(url: 'A', source: info, geometry: geometry))!;
    final fadeOwner = first.clone();
    first.dispose();
    final again =
        (await preparer.prepare(url: 'A', source: info, geometry: geometry))!;
    expect(rasters, 1);
    again.dispose();
    for (final url in ['B', 'C']) {
      (await preparer.prepare(url: url, source: info, geometry: geometry))!
          .dispose();
    }
    expect(preparer.cacheEntries, 2);
    expect(preparer.cacheBytes, lessThanOrEqualTo(16 * 1024 * 1024));
    expect(fadeOwner.image.debugDisposed, isFalse);
    final bytes = await fadeOwner.image.toByteData();
    expect(bytes, isNotNull);
    const changed = TvArtworkGeometry(Size(96, 64), 2);
    final resized =
        (await preparer.prepare(url: 'C', source: info, geometry: changed))!;
    expect(rasters, 4);
    expect(resized.image.width, 192);
    resized.dispose();
    preparer.invalidate(clearCache: true);
    expect(preparer.cacheEntries, 0);
    expect(preparer.cacheBytes, 0);
    expect(fadeOwner.image.debugDisposed, isFalse);
    fadeOwner.dispose();
    preparer.dispose();
    info.dispose();
  });

  test('dispose rejects a real raster result released after its owner is gone',
      () async {
    final info = ImageInfo(image: await _pattern());
    final rasterReady = Completer<void>();
    final release = Completer<void>();
    ui.Image? output;
    final preparer =
        TvArtworkPreparer(rasterizer: (image, scale, geometry) async {
      output = await rasterizeTvPortraitArtwork(image, scale, geometry);
      rasterReady.complete();
      await release.future;
      return output!;
    });
    final future = preparer.prepare(
        url: 'A',
        source: info,
        geometry: const TvArtworkGeometry(Size(96, 64), 1));
    await rasterReady.future;
    preparer.dispose();
    release.complete();
    expect(await future, isNull);
    expect(output!.debugDisposed, isTrue);
    expect(info.image.debugDisposed, isFalse);
    info.dispose();
  });

  test('geometry invalidation discards active and pending old viewport work',
      () async {
    final info = ImageInfo(image: await _pattern());
    final firstReady = Completer<void>();
    final release = Completer<void>();
    final outputs = <ui.Image>[];
    final preparer =
        TvArtworkPreparer(rasterizer: (image, scale, geometry) async {
      final output = await rasterizeTvPortraitArtwork(image, scale, geometry);
      outputs.add(output);
      if (outputs.length == 1) {
        firstReady.complete();
        await release.future;
      }
      return output;
    });
    const before = TvArtworkGeometry(Size(96, 64), 1);
    final active = preparer.prepare(url: 'A', source: info, geometry: before);
    await firstReady.future;
    final pending = preparer.prepare(url: 'B', source: info, geometry: before);
    preparer.invalidate(clearCache: true);
    expect(await pending, isNull);
    const after = TvArtworkGeometry(Size(96, 64), 2);
    final current = preparer.prepare(url: 'A', source: info, geometry: after);
    release.complete();
    expect(await active, isNull);
    final frame = (await current)!;
    expect(outputs, hasLength(2));
    expect(outputs.first.debugDisposed, isTrue);
    expect(frame.key.geometry, after);
    expect(frame.image.width, 192);
    frame.dispose();
    preparer.dispose();
    info.dispose();
  });

  test('oversized viewport retains original pixels without a prepared texture',
      () async {
    final info = ImageInfo(image: await _pattern());
    final preparer = TvArtworkPreparer();
    final frame = (await preparer.prepare(
      url: 'A',
      source: info,
      geometry: const TvArtworkGeometry(Size(3840, 2160), 1),
    ))!;
    expect(frame.key.prefiltered, isFalse);
    expect(frame.key.landscape, isFalse);
    expect(frame.image.isCloneOf(info.image), isTrue);
    expect(preparer.hasActivePreparation, isFalse);
    expect(preparer.cacheBytes, 0);
    frame.dispose();
    preparer.dispose();
    info.dispose();
  });
}
