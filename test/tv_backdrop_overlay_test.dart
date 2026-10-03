import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/tv_artwork_preparation.dart';
import 'package:kazumi/bean/widget/tv_backdrop_overlay.dart';

Widget _app(TvArtworkGeometry geometry, TvBackdropRasterizer rasterizer) =>
    MaterialApp(
        home: SizedBox.expand(
            child: TvBackdropOverlay(
      geometry: geometry,
      rasterizer: rasterizer,
    )));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'geometry changes queue latest only and release stale or disposed rasters',
      (tester) async {
    const a = TvArtworkGeometry(Size(48, 32), 1);
    const b = TvArtworkGeometry(Size(64, 40), 1);
    const c = TvArtworkGeometry(Size(80, 48), 2);
    const d = TvArtworkGeometry(Size(96, 64), 1);
    final firstReady = Completer<void>();
    final releaseFirst = Completer<void>();
    final lastReady = Completer<void>();
    final releaseLast = Completer<void>();
    final geometries = <TvArtworkGeometry>[];
    final images = <ui.Image>[];
    var active = 0;
    var maximumActive = 0;
    Future<ui.Image> rasterizer(TvArtworkGeometry geometry) async {
      ++active;
      maximumActive = active > maximumActive ? active : maximumActive;
      geometries.add(geometry);
      final image = await rasterizeTvBackdropOverlay(geometry);
      images.add(image);
      if (geometry == a) {
        firstReady.complete();
        await releaseFirst.future;
      } else if (geometry == d) {
        lastReady.complete();
        await releaseLast.future;
      }
      --active;
      return image;
    }

    await tester.pumpWidget(_app(a, rasterizer));
    await tester
        .runAsync(() => firstReady.future.timeout(const Duration(seconds: 5)));
    await tester.pumpWidget(_app(b, rasterizer));
    await tester.pumpWidget(_app(c, rasterizer));
    expect(geometries, [a]);
    releaseFirst.complete();
    for (var i = 0; i < 200 && find.byType(RawImage).evaluate().isEmpty; ++i) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    expect(geometries, [a, c]);
    expect(maximumActive, 1);
    expect(images.first.debugDisposed, isTrue);
    final display = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(display.width, 160);
    expect(display.height, 96);
    await tester.pumpWidget(_app(d, rasterizer));
    await tester
        .runAsync(() => lastReady.future.timeout(const Duration(seconds: 5)));
    await tester.pumpWidget(const SizedBox.shrink());
    releaseLast.complete();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
    expect(geometries, [a, c, d]);
    expect(images.every((image) => image.debugDisposed), isTrue);
    expect(display.debugDisposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'oversize geometry preserves gradients without allocating a texture',
      (tester) async {
    var requests = 0;
    await tester.pumpWidget(_app(
      const TvArtworkGeometry(Size(3840, 2160), 1),
      (geometry) async {
        ++requests;
        return rasterizeTvBackdropOverlay(geometry);
      },
    ));
    await tester.pump();
    expect(requests, 0);
    expect(find.byType(RawImage), findsNothing);
    expect(
        find.descendant(
            of: find.byType(TvBackdropOverlay),
            matching: find.byType(DecoratedBox)),
        findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'raster failure retains original gradients and does not retry each frame',
      (tester) async {
    var requests = 0;
    await tester.pumpWidget(_app(
      const TvArtworkGeometry(Size(96, 64), 1),
      (geometry) async {
        ++requests;
        throw StateError('controlled raster failure');
      },
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(requests, 1);
    expect(find.byType(RawImage), findsNothing);
    expect(
        find.descendant(
            of: find.byType(TvBackdropOverlay),
            matching: find.byType(DecoratedBox)),
        findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
