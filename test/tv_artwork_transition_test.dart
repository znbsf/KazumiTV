import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/tv_artwork.dart';
import 'package:kazumi/bean/widget/tv_artwork_preparation.dart';
import 'package:kazumi/bean/widget/tv_visuals.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';

import 'support/tv_focus_fixtures.dart';

// Seed exactly the production provider key; no HTTP or cache-manager IO runs.
final _readyUrls = <Completer<ImageInfo>, String>{};

Future<Completer<ImageInfo>> _pending(String url) async {
  final provider = ResizeImage.resizeIfNeeded(
    720,
    null,
    CachedNetworkImageProvider(url),
  );
  final key = await provider.obtainKey(ImageConfiguration.empty);
  final ready = Completer<ImageInfo>();
  _readyUrls[ready] = url;
  PaintingBinding.instance.imageCache.putIfAbsent(
    key,
    () => OneFrameImageStreamCompleter(ready.future),
  );
  return ready;
}

Future<ui.Image> _image(Color color, {int width = 80, int height = 120}) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

BangumiItem _item(int id, String url) => focusItem(id)..images = {'large': url};

Finder _frame(String url, {double? dpr}) => find.descendant(
      of: find.byWidgetPredicate((widget) =>
          widget is Opacity &&
          widget.key is ValueKey<TvArtworkKey> &&
          (widget.key! as ValueKey<TvArtworkKey>).value.url == url &&
          (dpr == null ||
              (widget.key! as ValueKey<TvArtworkKey>)
                      .value
                      .geometry
                      .devicePixelRatio ==
                  dpr)),
      matching: find.byType(RawImage),
    );

Widget _app(WidgetTester tester, {bool oled = false}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 180);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(body: TvAmbientBackdrop(oled: oled)),
  );
}

Future<void> _waitForFrame(WidgetTester tester, String url,
    {double? dpr}) async {
  // Wait for the real asynchronous engine raster, without advancing the
  // widget animation clock or replacing preparation with a mock.
  for (var attempt = 0; attempt < 200; ++attempt) {
    await tester.pump();
    if (_frame(url, dpr: dpr).evaluate().isNotEmpty) return;
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
  }
  fail('Real artwork preparation did not finish: $url');
}

Future<void> _completeAndBuild(
    WidgetTester tester, Completer<ImageInfo> ready, ui.Image image) async {
  ready.complete(ImageInfo(image: image));
  // The stream completion schedules a rebuild after the first pump. Build
  // AnimatedSwitcher in a separate frame before advancing its animation clock.
  await tester.pump();
  await tester.pump();
  await _waitForFrame(tester, _readyUrls[ready]!);
}

Future<void> _finish(
    WidgetTester tester, Completer<ImageInfo> ready, ui.Image image) async {
  await _completeAndBuild(tester, ready, image);
  final url = _readyUrls[ready]!;
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
  expect(_fade(tester, url), 1,
      reason: 'the initial cover must finish entering before it can fade out');
  // Flutter reaches the endpoint at 600ms, but reports the animation finished
  // on the first later frame (its interpolation simulation uses time > duration).
  // That status notification lets AnimatedSwitcher release outgoing children.
  await tester.pump(const Duration(milliseconds: 16));
}

double _fade(WidgetTester tester, String url) => tester
    .widget<FadeTransition>(
      find
          .ancestor(of: _frame(url), matching: find.byType(FadeTransition))
          .first,
    )
    .opacity
    .value;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    _readyUrls.clear();
    tvArtworkController.select(null);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  tearDown(() {
    tvArtworkController.select(null);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('260ms dwell and decode keep old pixels until a 600ms fade', (
    tester,
  ) async {
    const aUrl = 'https://fixture.invalid/artwork-dwell-a.png';
    const bUrl = 'https://fixture.invalid/artwork-dwell-b.png';
    final aReady = await _pending(aUrl);
    final bReady = await _pending(bUrl);
    final a = (await tester.runAsync(() => _image(Colors.red)))!;
    final b = (await tester.runAsync(() => _image(Colors.blue)))!;
    tvArtworkController.select(_item(1, aUrl));
    await tester.pumpWidget(_app(tester));
    await tester.pump(const Duration(milliseconds: 259));
    expect(find.byType(RawImage), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    await _finish(tester, aReady, a);
    expect(_frame(aUrl), findsOneWidget);
    final outgoingPixels = tester.widget<RawImage>(_frame(aUrl)).image!;

    tvArtworkController.select(_item(2, bUrl));
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(seconds: 2));
    expect(_frame(aUrl), findsOneWidget,
        reason: 'decode latency must not create a black interval');
    expect(_frame(bUrl), findsNothing);
    await _completeAndBuild(tester, bReady, b);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_frame(aUrl), findsOneWidget);
    expect(_frame(bUrl), findsOneWidget);
    expect(_fade(tester, aUrl), inExclusiveRange(0, 1));
    expect(_fade(tester, bUrl), inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(_fade(tester, aUrl), closeTo(0, .000001),
        reason: 'the old cover must stop painting at the 600ms endpoint');
    expect(_fade(tester, bUrl), 1);
    expect(outgoingPixels.debugDisposed, isFalse,
        reason:
            'the outgoing widget owns its pixels through the fade endpoint');
    await tester.pump(const Duration(milliseconds: 16));
    expect(_frame(aUrl), findsNothing);
    expect(outgoingPixels.debugDisposed, isTrue);
    expect(_frame(bUrl), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A to B to A rejects B completing after the returned selection', (
    tester,
  ) async {
    const aUrl = 'https://fixture.invalid/artwork-return-a.png';
    const bUrl = 'https://fixture.invalid/artwork-return-b.png';
    final aReady = await _pending(aUrl);
    final bReady = await _pending(bUrl);
    final a = (await tester.runAsync(() => _image(Colors.red)))!;
    final b = (await tester.runAsync(() => _image(Colors.blue)))!;
    final aItem = _item(1, aUrl);
    tvArtworkController.select(aItem);
    await tester.pumpWidget(_app(tester));
    await tester.pump(const Duration(milliseconds: 260));
    await _finish(tester, aReady, a);
    tvArtworkController.select(_item(2, bUrl));
    await tester.pump(const Duration(milliseconds: 260));
    tvArtworkController.select(aItem);
    await tester.pump(const Duration(milliseconds: 260));
    bReady.complete(ImageInfo(image: b));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(_frame(aUrl), findsOneWidget);
    expect(_frame(bUrl), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an earlier pending cover cannot replace the newly decoded work',
      (
    tester,
  ) async {
    const aUrl = 'https://fixture.invalid/artwork-late-a.png';
    const bUrl = 'https://fixture.invalid/artwork-late-b.png';
    final aReady = await _pending(aUrl);
    final bReady = await _pending(bUrl);
    final a = (await tester.runAsync(() => _image(Colors.red)))!;
    final b = (await tester.runAsync(() => _image(Colors.blue)))!;
    tvArtworkController.select(_item(1, aUrl));
    await tester.pumpWidget(_app(tester));
    await tester.pump(const Duration(milliseconds: 260));
    tvArtworkController.select(_item(2, bUrl));
    await tester.pump(const Duration(milliseconds: 260));
    await _finish(tester, bReady, b);
    aReady.complete(ImageInfo(image: a));
    await tester.pump(const Duration(seconds: 1));
    expect(_frame(bUrl), findsOneWidget);
    expect(_frame(aUrl), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing covers fade to neutral and OLED clears art immediately',
      (
    tester,
  ) async {
    const url = 'https://fixture.invalid/artwork-oled.png';
    final ready = await _pending(url);
    final image = (await tester.runAsync(() => _image(Colors.green)))!;
    final item = _item(1, url);
    tvArtworkController.select(item);
    await tester.pumpWidget(_app(tester));
    await tester.pump(const Duration(milliseconds: 260));
    await _finish(tester, ready, image);
    tvArtworkController.select(focusItem(2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_frame(url), findsOneWidget);
    expect(_fade(tester, url), inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(_fade(tester, url), closeTo(0, .000001));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_frame(url), findsNothing);
    final background = find.descendant(
      of: find.byType(TvAmbientBackdrop),
      matching: find.byType(ColoredBox),
    );
    expect(tester.widget<ColoredBox>(background).color, TvVisuals.background);

    tvArtworkController.select(item);
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(_fade(tester, url), 1);
    await tester.pump(const Duration(milliseconds: 16));
    expect(_frame(url), findsOneWidget);
    await tester.pumpWidget(_app(tester, oled: true));
    expect(find.byType(RawImage), findsNothing);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(tester.widget<ColoredBox>(background).color, Colors.black);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(RawImage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'portrait art is softened while a wide cover fills the same window', (
    tester,
  ) async {
    const portraitUrl = 'https://fixture.invalid/artwork-portrait.png';
    const wideUrl = 'https://fixture.invalid/artwork-wide.png';
    final portraitReady = await _pending(portraitUrl);
    final wideReady = await _pending(wideUrl);
    final portrait = (await tester.runAsync(() => _image(Colors.red)))!;
    final wide = (await tester
        .runAsync(() => _image(Colors.blue, width: 160, height: 90)))!;
    tvArtworkController.select(_item(1, portraitUrl));
    await tester.pumpWidget(_app(tester));
    await tester.pump(const Duration(milliseconds: 260));
    await _finish(tester, portraitReady, portrait);
    expect(find.byType(ImageFiltered), findsNothing,
        reason: 'portrait blur is prepared once, outside the fade paint path');
    final portraitOpacity = tester.widget<Opacity>(
      find
          .ancestor(of: _frame(portraitUrl), matching: find.byType(Opacity))
          .first,
    );
    expect(portraitOpacity.opacity, .84);
    final window = tester.getSize(find.byType(TvAmbientBackdrop));
    expect(tester.getSize(_frame(portraitUrl)), window);
    tvArtworkController.select(_item(2, wideUrl));
    await tester.pump(const Duration(milliseconds: 260));
    await _finish(tester, wideReady, wide);
    expect(find.byType(ImageFiltered), findsNothing);
    final wideOpacity = tester.widget<Opacity>(
      find.ancestor(of: _frame(wideUrl), matching: find.byType(Opacity)).first,
    );
    expect(wideOpacity.opacity, 1);
    expect(tester.getSize(_frame(wideUrl)), window);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed new artwork fades out the unrelated previous cover', (
    tester,
  ) async {
    const oldUrl = 'https://fixture.invalid/artwork-failure-old.png';
    const failedUrl = 'https://fixture.invalid/artwork-failure-new.png';
    final oldReady = await _pending(oldUrl);
    final failedReady = await _pending(failedUrl);
    final old = (await tester.runAsync(() => _image(Colors.red)))!;
    tvArtworkController.select(_item(1, oldUrl));
    await tester.pumpWidget(_app(tester));
    await tester.pump(const Duration(milliseconds: 260));
    await _finish(tester, oldReady, old);
    tvArtworkController.select(_item(2, failedUrl));
    await tester.pump(const Duration(milliseconds: 260));
    failedReady.completeError(StateError('controlled offline artwork failure'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(_fade(tester, oldUrl), closeTo(0, .000001));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_frame(oldUrl), findsNothing);
    expect(find.byType(RawImage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'DPR changes prepare new pixels before replacing the old geometry',
      (tester) async {
    const url = 'https://fixture.invalid/artwork-geometry.png';
    final ready = await _pending(url);
    final image = (await tester.runAsync(() => _image(Colors.red)))!;
    tvArtworkController.select(_item(1, url));
    await tester.pumpWidget(_app(tester));
    await tester.pump(const Duration(milliseconds: 260));
    await _finish(tester, ready, image);
    expect(tester.widget<RawImage>(_frame(url, dpr: 1)).image!.width, 320);

    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(640, 360);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 259));
    expect(_frame(url, dpr: 1), findsOneWidget);
    expect(_frame(url, dpr: 2), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    await _waitForFrame(tester, url, dpr: 2);
    expect(_frame(url, dpr: 1), findsOneWidget);
    expect(tester.widget<RawImage>(_frame(url, dpr: 2)).image!.width, 640);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_frame(url, dpr: 1), findsNothing);
    expect(_frame(url, dpr: 2), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
