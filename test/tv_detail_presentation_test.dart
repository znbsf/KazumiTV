import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/widget/tv_visuals.dart';
import 'package:kazumi/pages/info/info_tabview.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/utils/constants.dart';

ui.Image _poster(Color color, int width, int height) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(width, height);
  picture.dispose();
  return image;
}

Future<Completer<ImageInfo>> _pending(String url, int width) async {
  final provider = ResizeImage.resizeIfNeeded(
    width,
    null,
    CachedNetworkImageProvider(url),
  );
  final key = await provider.obtainKey(ImageConfiguration.empty);
  final ready = Completer<ImageInfo>();
  PaintingBinding.instance.imageCache.putIfAbsent(
    key,
    () => OneFrameImageStreamCompleter(ready.future),
  );
  return ready;
}

Widget _app(Widget child) => MaterialApp(
      theme: TvVisuals.theme(ThemeData()),
      home: Scaffold(body: Center(child: child)),
    );

Finder _frame(ui.Image image) => find.byWidgetPredicate(
      (widget) => widget is RawImage && widget.image?.isCloneOf(image) == true,
    );

void _useLogicalPixels(WidgetTester tester) {
  // Production decode keys multiply the layout size by devicePixelRatio. Keep
  // these seeded 80/158-pixel providers identical to the actual widget request.
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() {
    TvMode.setEnabledForTesting(false);
    NetworkImgLayer.clearTvCoverMemory();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('sliding TV page covers the previous page throughout transition',
      (tester) async {
    _useLogicalPixels(tester);
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    final navigator = GlobalKey<NavigatorState>();
    final boundary = GlobalKey();
    const incoming = ValueKey('incoming-page');
    await tester.pumpWidget(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        navigatorKey: navigator,
        theme: TvVisuals.theme(ThemeData(
          platform: TargetPlatform.android,
          pageTransitionsTheme: pageTransitionsTheme2024,
        )),
        home: const Scaffold(
            body: ColoredBox(color: Colors.red, child: SizedBox.expand())),
      ),
    ));
    await tester.pumpAndSettle();
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) =>
            const Scaffold(key: incoming, body: SizedBox.expand())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    Future<void> expectCovered() async {
      final rect = tester.getRect(find.byKey(incoming));
      expect(rect.left, greaterThan(0), reason: 'sample during the slide');
      expect(rect.left, lessThan(720));
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final frame = render.toImageSync();
      final bytes = await tester.runAsync(() => frame.toByteData());
      // Well inside the moving page, away from its edge shadow. The old red
      // page is still painted underneath; it must not bleed into this pixel.
      expect(bytes!.getUint32((400 * frame.width + 760) * 4), 0x101611FF);
      frame.dispose();
    }

    await expectCovered();
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    await expectCovered();
    await tester.pumpAndSettle();
    expect(find.byKey(incoming), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'list cover stays visible while larger detail decode is delayed',
    (tester) async {
      _useLogicalPixels(tester);
      const url = 'https://fixture.invalid/detail-size.png';
      final small = _poster(Colors.red, 80, 120);
      (await _pending(url, 80)).complete(ImageInfo(image: small));
      final largeReady = await _pending(url, 158);
      final detailBoundary = GlobalKey();
      await tester.pumpWidget(
        _app(
          const NetworkImgLayer(
            src: url,
            width: 80,
            height: 120,
            fadeInDuration: Duration.zero,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_frame(small), findsOneWidget);

      await tester.pumpWidget(
        _app(
          RepaintBoundary(
            key: detailBoundary,
            child: const NetworkImgLayer(
              src: url,
              placeholderSrc: url,
              key: ValueKey('detail'),
              width: 158,
              height: 237,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(_frame(small), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      final switcher = tester.widget<AnimatedSwitcher>(find.descendant(
        of: find.byType(NetworkImgLayer),
        matching: find.byType(AnimatedSwitcher),
      ));
      expect(switcher.duration, const Duration(milliseconds: 180));

      final large = _poster(Colors.red, 158, 237);
      largeReady.complete(ImageInfo(image: large));
      // Stream completion schedules setState after this first pump. Build the
      // switcher in a separate frame before advancing its animation clock.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(_frame(small), findsOneWidget);
      expect(_frame(large), findsOneWidget);
      final incoming = tester.widget<FadeTransition>(
        find
            .ancestor(of: _frame(large), matching: find.byType(FadeTransition))
            .first,
      );
      expect(incoming.opacity.value, greaterThan(0));
      expect(incoming.opacity.value, lessThan(1));
      // Two identical opaque colors at different decode sizes must retain
      // brightness during their handoff, regardless of the underlying page.
      final surface = detailBoundary.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final pixels = surface.toImageSync();
      final rgba = await tester.runAsync(() => pixels.toByteData());
      expect(rgba!.getUint32((118 * pixels.width + 79) * 4), 0xF44336FF);
      pixels.dispose();
      final outgoing = tester.widget<FadeTransition>(
        find
            .ancestor(of: _frame(small), matching: find.byType(FadeTransition))
            .first,
      );
      expect(outgoing.opacity.value, 1);
      await tester.pump(const Duration(milliseconds: 90));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_frame(small), findsNothing);
      expect(_frame(large), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'different detail URL retains the displayed list cover on failure',
    (tester) async {
      _useLogicalPixels(tester);
      const listUrl = 'https://fixture.invalid/list-cover.png';
      const largeUrl = 'https://fixture.invalid/large-cover.png';
      final list = _poster(Colors.green, 80, 120);
      final catalog = {
        'medium': listUrl,
        'common': 'https://fixture.invalid/not-yet-displayed-common.png',
        'large': largeUrl,
      };
      (await _pending(listUrl, 80)).complete(ImageInfo(image: list));
      final largeReady = await _pending(largeUrl, 158);
      await tester.pumpWidget(
        _app(
          const NetworkImgLayer(
            src: listUrl,
            width: 80,
            height: 120,
            fadeInDuration: Duration.zero,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _app(
          NetworkImgLayer(
            key: ValueKey('detail'),
            src: largeUrl,
            placeholderSrc: NetworkImgLayer.tvInitialCoverUrl(catalog),
            width: 158,
            height: 237,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(_frame(list), findsOneWidget);
      largeReady.completeError(StateError('controlled delayed cover failure'));
      await tester.pumpAndSettle();
      expect(_frame(list), findsOneWidget);
      expect(find.text('重试封面'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switching works rejects the late previous cover', (
    tester,
  ) async {
    _useLogicalPixels(tester);
    const a = 'https://fixture.invalid/work-a.png';
    const b = 'https://fixture.invalid/work-b.png';
    final aReady = await _pending(a, 158);
    final bReady = await _pending(b, 158);
    await tester.pumpWidget(
      _app(
        const NetworkImgLayer(
          src: a,
          placeholderSrc: a,
          width: 158,
          height: 237,
        ),
      ),
    );
    await tester.pumpWidget(
      _app(
        const NetworkImgLayer(
          src: b,
          placeholderSrc: b,
          width: 158,
          height: 237,
        ),
      ),
    );
    final old = _poster(Colors.red, 158, 237);
    aReady.complete(ImageInfo(image: old));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_frame(old), findsNothing);
    final current = _poster(Colors.blue, 158, 237);
    bReady.complete(ImageInfo(image: current));
    await tester.pumpAndSettle();
    expect(_frame(current), findsOneWidget);
    expect(_frame(old), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('synopsis remote scroll and Back preserve the detail route', (
    tester,
  ) async {
    final longSummary = List.generate(120, (i) => '第 $i 行简介。').join('\n');
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            return TextButton(
              autofocus: true,
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    TvSynopsisReader(title: '作品', summary: longSummary),
              ),
              child: const Text('阅读完整简介'),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final scroll = tester.widget<SingleChildScrollView>(
      find.descendant(
        of: find.byType(TvSynopsisReader),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(scroll.controller!.offset, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(scroll.controller!.offset, greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(scroll.controller!.offset, 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TvSynopsisReader), findsNothing);
    expect(find.text('阅读完整简介'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.context, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
