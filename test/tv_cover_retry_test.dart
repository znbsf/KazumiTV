import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Covers implements BaseCacheManager {
  _Covers(this.cover);
  final FileInfo cover;
  final calls = <String, int>{};
  final errors = <String, List<Object>>{};
  final pending = <String, StreamController<FileResponse>>{};

  @override
  Stream<FileResponse> getFileStream(String url,
      {String? key, Map<String, String>? headers, bool withProgress = false}) {
    final attempt = calls.update(url, (n) => n + 1, ifAbsent: () => 1);
    if (pending.containsKey(url)) return pending[url]!.stream;
    final failures = errors[url] ?? [];
    if (attempt <= failures.length) return Stream.error(failures[attempt - 1]);
    return Stream.value(FileInfo(cover.file, FileSource.Online,
        DateTime.now().add(const Duration(days: 1)), url));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _url = 'https://fixture.invalid/cover.png';
const _other = 'https://fixture.invalid/other.png';
const _socket = SocketException('lossy line');

Widget _cover(
        {String url = _url,
        bool detail = true,
        double width = 80,
        ValueChanged<bool>? onRetryVisibilityChanged}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: NetworkImgLayer(
            src: url,
            placeholderSrc: detail ? 'https://fixture.invalid/list.png' : null,
            width: width,
            height: 120,
            tvOnRetryVisibilityChanged: onRetryVisibilityChanged,
          ),
        ),
      ),
    );

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
}

Future<void> _frame(WidgetTester tester) async {
  // Let the engine's asynchronous PNG decoder complete; retry clocks stay fake.
  for (var i = 0; i < 10; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await _flush(tester);
    if (find
        .byWidgetPredicate((w) => w.runtimeType.toString() == '_TvCoverFrame')
        .evaluate()
        .isNotEmpty) {
      return;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List png;
  late FileInfo cover;
  late Directory temp;
  late Level oldLogLevel;
  late PathProviderPlatform oldPaths;
  setUpAll(() async {
    oldLogLevel = Logger.level;
    Logger.level = Level.off;
    temp = await Directory.systemTemp.createTemp('tv_cover_retry_');
    oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(temp.path);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.red, BlendMode.src);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(2, 3);
    picture.dispose();
    png = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    image.dispose();
    final file = await MemoryCacheSystem().createFile('cover.png');
    await file.writeAsBytes(png);
    cover = FileInfo(file, FileSource.Online,
        DateTime.now().add(const Duration(days: 1)), _url);
  });
  tearDownAll(() async {
    PathProviderPlatform.instance = oldPaths;
    await temp.delete(recursive: true);
    Logger.level = oldLogLevel;
  });
  late _Covers cache;
  late BaseCacheManager oldCache;
  setUp(() {
    TvMode.setEnabledForTesting(true);
    oldCache = CachedNetworkImageProvider.defaultCacheManager;
    cache = _Covers(cover);
    CachedNetworkImageProvider.defaultCacheManager = cache;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  tearDown(() {
    CachedNetworkImageProvider.defaultCacheManager = oldCache;
    NetworkImgLayer.tvCoverRetryDelaysForTesting = null;
    NetworkImgLayer.clearTvCoverMemory();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    TvMode.setEnabledForTesting(false);
  });

  testWidgets(
      'cover callback 5 retry round, URL reset and build-safe parent updates',
      (tester) async {
    cache.errors[_url] = List.filled(6, _socket);
    NetworkImgLayer.tvCoverRetryDelaysForTesting = const [
      Duration(milliseconds: 1),
      Duration(milliseconds: 2),
    ];
    final events = <bool>[];
    var url = _url;
    var showCover = true;
    late StateSetter update;
    await tester.pumpWidget(StatefulBuilder(builder: (context, setState) {
      update = setState;
      return showCover
          ? _cover(
              url: url,
              onRetryVisibilityChanged: (visible) {
                if (!context.mounted) return;
                setState(() => events.add(visible));
              })
          : const SizedBox();
    }));
    await _flush(tester);
    expect(events, [false]);
    Future<void> exhaust() async {
      for (var i = 0; i < 2; i++) {
        await tester.pump(const Duration(milliseconds: 3));
        await _flush(tester);
      }
    }

    await exhaust();
    expect(events, [false, true]);
    await tester.pump();
    await tester.pump();
    expect(events, [false, true],
        reason: 'unchanged visibility is not repeated');
    await tester.tap(find.text('重试封面'));
    await _flush(tester);
    expect(events, [false, true, false]);
    expect(cache.calls[_url], 4);
    await exhaust();
    expect(events, [false, true, false, true]);

    cache.pending[_other] = StreamController<FileResponse>.broadcast();
    update(() => url = _other);
    await tester.pump();
    await _flush(tester);
    expect(events, [false, true, false, true, false]);
    expect(find.text('重试封面'), findsNothing);
    // Keep the replacement request unresolved: no real PNG-decoder waits.
    cache.pending[_other]!
        .addError(const HttpExceptionWithStatus(404, 'missing'));
    await _flush(tester);
    expect(events.last, isTrue);
    update(() => showCover = false);
    await tester.pump();
    expect(events.last, isFalse,
        reason: 'a surviving owner clears disposed retry UI');
    unawaited(cache.pending[_other]!.close());
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('cover callback skips a queued visibility update after unmount',
      (tester) async {
    final events = <bool>[];
    cache.pending[_url] = StreamController<FileResponse>.broadcast();
    await tester.pumpWidget(_cover(onRetryVisibilityChanged: events.add));
    expect(events, [false]);
    cache.pending[_url]!.addError(HttpExceptionWithStatus(404, 'missing'));
    // Deliver the failure, then dispose before rebuilding the dirty image.
    await tester.idle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(events, [false]);
    unawaited(cache.pending[_url]!.close());
    expect(tester.takeException(), isNull);
  });

  for (final detail in [false, true]) {
    testWidgets(
        'D12 rule 1 transient failure shows a frame without failure UI detail=$detail',
        (tester) async {
      cache.errors[_url] = [_socket];
      await tester.pumpWidget(_cover(detail: detail));
      await _flush(tester);
      expect(cache.calls[_url], 1);
      expect(find.text('重试封面'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1999));
      expect(cache.calls[_url], 1);
      await tester.pump(const Duration(milliseconds: 1));
      await _frame(tester);
      expect(cache.calls[_url], 2);
      expect(
          find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_TvCoverFrame'),
          findsOneWidget);
      expect(find.text('重试封面'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('D12 rule 2 exactly three fetches, failure only after third',
      (tester) async {
    cache.errors[_url] = List.filled(6, _socket);
    await tester.pumpWidget(_cover());
    await _flush(tester);
    expect(cache.calls[_url], 1);
    expect(find.text('重试封面'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await _flush(tester);
    expect(cache.calls[_url], 2);
    expect(find.text('重试封面'), findsNothing);
    await tester.pump(const Duration(milliseconds: 5999));
    expect(cache.calls[_url], 2);
    expect(find.text('重试封面'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    await _flush(tester);
    expect(cache.calls[_url], 3);
    expect(find.text('重试封面'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    expect(cache.calls[_url], 3);
  });

  testWidgets(
      'D12 rule 3 manual retry starts a full fresh round and fetches again',
      (tester) async {
    cache.errors[_url] = List.filled(6, _socket);
    await tester.pumpWidget(_cover());
    await _flush(tester);
    await tester.pump(const Duration(seconds: 2));
    await _flush(tester);
    await tester.pump(const Duration(seconds: 6));
    await _flush(tester);
    expect(find.text('重试封面'), findsOneWidget);
    await tester.tap(find.text('重试封面'));
    await _flush(tester);
    expect(cache.calls[_url], 4);
    expect(find.text('重试封面'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await _flush(tester);
    expect(cache.calls[_url], 5);
    expect(find.text('重试封面'), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    await _flush(tester);
    expect(cache.calls[_url], 6);
    expect(find.text('重试封面'), findsOneWidget);
  });

  testWidgets(
      'D12 keeps the displayed list frame through retries and manual recovery',
      (tester) async {
    const list = 'https://fixture.invalid/list.png';
    await tester.pumpWidget(_cover(url: list, detail: false));
    await _frame(tester);
    final displayed = tester
        .widget<RawImage>(find.descendant(
          of: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_TvCoverFrame'),
          matching: find.byType(RawImage),
        ))
        .image!
        .clone();
    addTearDown(displayed.dispose);
    final held = find.byWidgetPredicate(
        (w) => w is RawImage && w.image?.isCloneOf(displayed) == true);
    cache.errors[_url] = List.filled(3, _socket);
    await tester.pumpWidget(_cover());
    await _flush(tester);
    expect(held, findsOneWidget);
    expect(find.text('重试封面'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await _flush(tester);
    expect(held, findsOneWidget);
    expect(find.text('重试封面'), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    await _flush(tester);
    expect(held, findsOneWidget);
    expect(find.text('重试封面'), findsOneWidget);
    await tester.tap(find.text('重试封面'));
    await _flush(tester);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(cache.calls, {list: 1, _url: 4});
    expect(held, findsNothing);
    expect(find.text('重试封面'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final status in [400, 401, 404, 408, 429]) {
    testWidgets('D12 rule 4 HTTP $status classification', (tester) async {
      cache.errors[_url] =
          List.filled(3, HttpExceptionWithStatus(status, 'fixture'));
      await tester.pumpWidget(_cover());
      await _flush(tester);
      final transient = status == 408 || status == 429;
      expect(find.text('重试封面'), transient ? findsNothing : findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await _flush(tester);
      expect(cache.calls[_url], transient ? 2 : 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    });
  }

  testWidgets('D12 rule 5 resized cached provider really refetches on retry',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    cache.errors[_url] = [_socket];
    await tester.pumpWidget(_cover(width: 93));
    await _flush(tester);
    final provider = ResizeImage.resizeIfNeeded(
        93, null, const CachedNetworkImageProvider(_url));
    final key = await provider.obtainKey(ImageConfiguration.empty);
    expect(key, isA<ResizeImageKey>());
    expect(cache.calls[_url], 1);
    // This SDK also evicts ResizeImage errors. Reproduce a retained error under
    // the *outer* key so this test proves our eviction, independently of that
    // SDK safeguard. A resolve without evict would replay this completer.
    final retained =
        OneFrameImageStreamCompleter(Future<ImageInfo>.error(_socket));
    final listener = ImageStreamListener((_, __) {}, onError: (_, __) {});
    retained.addListener(listener);
    PaintingBinding.instance.imageCache.putIfAbsent(key, () => retained);
    await _flush(tester);
    expect(PaintingBinding.instance.imageCache.containsKey(key), isTrue);
    addTearDown(() => retained.removeListener(listener));
    await tester.pump(const Duration(seconds: 2));
    await _frame(tester);
    expect(cache.calls[_url], 2,
        reason: 'must download again, not replay the cached error');
    expect(
        find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_TvCoverFrame'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('D12 rule 6 dispose cancels a pending retry timer',
      (tester) async {
    cache.errors[_url] = List.filled(3, _socket);
    await tester.pumpWidget(_cover());
    await _flush(tester);
    expect(cache.calls[_url], 1);
    await tester.pumpWidget(const SizedBox());
    // The test binding also asserts that no retry timer survives disposal.
    expect(cache.calls[_url], 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('D12 rule 7 url change cancels old retry and resets attempts',
      (tester) async {
    cache.errors[_url] = List.filled(3, _socket);
    cache.errors[_other] = List.filled(3, _socket);
    await tester.pumpWidget(_cover());
    await _flush(tester);
    await tester.pump(const Duration(seconds: 2));
    await _flush(tester);
    expect(cache.calls[_url], 2);
    await tester.pumpWidget(_cover(url: _other));
    await _flush(tester);
    expect(cache.calls[_other], 1);
    await tester.pump(const Duration(seconds: 2));
    await _flush(tester);
    expect(cache.calls[_other], 2);
    expect(find.text('重试封面'), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    await _flush(tester);
    expect(cache.calls, {_url: 2, _other: 3});
    expect(find.text('重试封面'), findsOneWidget);
  });

  testWidgets('D12 empty url leaves no pending retry timer', (tester) async {
    cache.errors[_url] = [_socket];
    await tester.pumpWidget(_cover(detail: false));
    await _flush(tester);
    await tester.pumpWidget(_cover(url: '', detail: false));
    await _flush(tester);
    expect(cache.calls, {_url: 1});
    expect(tester.takeException(), isNull);
    // No clock advance: the binding catches an uncancelled pending timer.
  });

  testWidgets('D12 provider size change gets a fresh retry budget',
      (tester) async {
    NetworkImgLayer.tvCoverRetryDelaysForTesting = [
      const Duration(milliseconds: 20),
      const Duration(milliseconds: 60),
    ];
    cache.errors[_url] = List.filled(6, _socket);
    await tester.pumpWidget(_cover());
    await _flush(tester);
    await tester.pump(const Duration(milliseconds: 20));
    await _flush(tester);
    expect(cache.calls[_url], 2);
    await tester.pumpWidget(_cover(width: 90));
    await _flush(tester);
    expect(cache.calls[_url], 3);
    await tester.pump(const Duration(milliseconds: 20));
    await _flush(tester);
    expect(cache.calls[_url], 4);
    expect(find.text('重试封面'), findsNothing);
    await tester.pump(const Duration(milliseconds: 60));
    await _flush(tester);
    expect(cache.calls[_url], 5);
    expect(find.text('重试封面'), findsOneWidget);
  });

  testWidgets(
      'D12 empty url cancels retries; late old stream cannot update new url',
      (tester) async {
    cache.errors[_url] = [_socket];
    await tester.pumpWidget(_cover(detail: false));
    await _flush(tester);
    await tester.pumpWidget(_cover(url: '', detail: false));
    await tester.pump(const Duration(seconds: 10));
    expect(cache.calls[_url], 1);
    final old = StreamController<FileResponse>();
    cache.pending[_url] = old;
    await tester.pumpWidget(_cover(detail: false));
    await _flush(tester);
    await tester.pumpWidget(_cover(url: _other, detail: false));
    await _frame(tester);
    old.addError(_socket);
    await _flush(tester);
    unawaited(old.close());
    await tester.pump(const Duration(seconds: 10));
    expect(cache.calls[_other], 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
