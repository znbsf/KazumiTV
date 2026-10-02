import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/video_source/video_source_format.dart';
import 'package:kazumi/services/video_source/video_source_service.dart';
import 'package:kazumi/services/video_source/webview_video_source_service.dart';
import 'package:kazumi/webview/video/video_webview_controller.dart';

const _firstPage = 'https://example.test/episode/1';
const _secondPage = 'https://example.test/episode/2';
const _thirdPage = 'https://example.test/episode/3';
const _firstVideo = 'https://example.test/video/1.m3u8';
const _secondVideo = 'https://example.test/video/2.mp4';
const _staleVideo = 'https://example.test/video/stale.m3u8';

Future<void> _flushAsync() => Future<void>.delayed(Duration.zero);

void main() {
  for (final useLegacyParser in [true, false]) {
    test('captures early URL before load completes (legacy=$useLegacyParser)',
        () async {
      final loadGate = Completer<void>();
      final controller = _FakeWebviewController();
      controller.onLoad = (_) {
        // Deliberately synchronous: the service must already be listening.
        expect(controller.hasParserListener, isTrue);
        controller.emit(_firstVideo, format: VideoSourceFormat.hls);
        return loadGate.future;
      };
      final service =
          WebViewVideoSourceService(controllerFactory: () => controller);
      addTearDown(service.dispose);

      var completed = false;
      final resolve = service.resolve(
        _firstPage,
        useLegacyParser: useLegacyParser,
        offset: 42,
      )..then((_) => completed = true);
      await controller.firstLoadStarted.future;
      await _flushAsync();
      expect(completed, isFalse);
      expect(controller.unloads, 0);

      loadGate.complete();
      final source = await resolve;
      expect(source.url, _firstVideo);
      expect(source.offset, 42);
      expect(source.format, VideoSourceFormat.hls);
      expect(source.type, VideoSourceType.online);
      expect(controller.loads.single.useLegacyParser, useLegacyParser);
      expect(controller.unloads, 1);
      expect(controller.hasParserListener, isFalse);
      expect(controller.disposals, 0);
    });
  }

  test('superseding request waits for old load and unload, ignoring late URLs',
      () async {
    final loadGate = Completer<void>();
    final unloadGate = Completer<void>();
    final controller = _FakeWebviewController();
    controller.onLoad = (url) {
      if (url == _firstPage) return loadGate.future;
      controller.emit(_secondVideo);
      return Future<void>.value();
    };
    controller.onUnload = () =>
        controller.unloads == 1 ? unloadGate.future : Future<void>.value();
    final service =
        WebViewVideoSourceService(controllerFactory: () => controller);
    addTearDown(service.dispose);

    final first = service.resolve(_firstPage, useLegacyParser: true);
    final cancelled =
        expectLater(first, throwsA(isA<VideoSourceCancelledException>()));
    await controller.firstLoadStarted.future;
    final second =
        service.resolve(_secondPage, useLegacyParser: false, offset: 7);
    await _flushAsync();
    expect(controller.hasParserListener, isFalse);
    expect(controller.loads.map((load) => load.url), [_firstPage]);
    controller.emit(_staleVideo);
    loadGate.complete();
    await _flushAsync();
    expect(controller.unloads, 1);
    expect(controller.loads, hasLength(1));
    controller.emit(_staleVideo);
    unloadGate.complete();

    await cancelled;
    final source = await second;
    expect(source.url, _secondVideo);
    expect(source.offset, 7);
    expect(controller.loads.map((load) => load.url), [_firstPage, _secondPage]);
    expect(controller.initializations, 1);
    expect(controller.unloads, 2);
    expect(controller.hasParserListener, isFalse);
  });

  test('superseded queued request never loads its page', () async {
    final unloadGate = Completer<void>();
    final controller = _FakeWebviewController();
    controller.onLoad = (url) {
      if (url == _thirdPage) controller.emit(_secondVideo);
      return Future<void>.value();
    };
    controller.onUnload = () =>
        controller.unloads == 1 ? unloadGate.future : Future<void>.value();
    final service =
        WebViewVideoSourceService(controllerFactory: () => controller);
    addTearDown(service.dispose);

    final first = service.resolve(_firstPage, useLegacyParser: false);
    final firstCancelled =
        expectLater(first, throwsA(isA<VideoSourceCancelledException>()));
    await controller.firstLoadStarted.future;
    final second = service.resolve(_secondPage, useLegacyParser: false);
    final secondCancelled =
        expectLater(second, throwsA(isA<VideoSourceCancelledException>()));
    final third = service.resolve(_thirdPage, useLegacyParser: false);
    await _flushAsync();
    expect(controller.loads.map((load) => load.url), [_firstPage]);
    controller.emit(_staleVideo);
    unloadGate.complete();

    await Future.wait([firstCancelled, secondCancelled]);
    expect((await third).url, _secondVideo);
    expect(controller.loads.map((load) => load.url), [_firstPage, _thirdPage]);
    expect(controller.unloads, 2);
  });

  test('explicit cancel detaches parser before unloading and permits reuse',
      () async {
    final unloadGate = Completer<void>();
    final controller = _FakeWebviewController();
    controller.onUnload = () =>
        controller.unloads == 1 ? unloadGate.future : Future<void>.value();
    final service =
        WebViewVideoSourceService(controllerFactory: () => controller);
    addTearDown(service.dispose);

    final first = service.resolve(_firstPage, useLegacyParser: true);
    final cancelled =
        expectLater(first, throwsA(isA<VideoSourceCancelledException>()));
    await controller.firstLoadStarted.future;
    service.cancel();
    await _flushAsync();
    expect(controller.hasParserListener, isFalse);
    expect(controller.unloads, 1);
    controller.emit(_staleVideo);
    unloadGate.complete();
    await cancelled;

    controller.onLoad = (_) {
      controller.emit(_secondVideo);
      return Future<void>.value();
    };
    expect((await service.resolve(_secondPage, useLegacyParser: false)).url,
        _secondVideo);
    expect(controller.initializations, 1);
    expect(controller.hasParserListener, isFalse);
  });

  test('timeout removes parser subscription and does not poison next request',
      () async {
    final controller = _FakeWebviewController();
    final service =
        WebViewVideoSourceService(controllerFactory: () => controller);
    addTearDown(service.dispose);

    const timeout = Duration(milliseconds: 20);
    await expectLater(
      service.resolve(_firstPage, useLegacyParser: false, timeout: timeout),
      throwsA(isA<VideoSourceTimeoutException>()
          .having((error) => error.timeout, 'timeout', timeout)),
    );
    expect(controller.hasParserListener, isFalse);
    expect(controller.unloads, 1);
    controller.emit(_staleVideo);
    controller.onLoad = (_) {
      controller.emit(_secondVideo);
      return Future<void>.value();
    };
    expect((await service.resolve(_secondPage, useLegacyParser: false)).url,
        _secondVideo);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(controller.unloads, 2);
    expect(controller.hasParserListener, isFalse);
  });

  test('load failure cleans subscription and preserves original error',
      () async {
    final failure = StateError('load failed');
    final controller = _FakeWebviewController()
      ..onLoad = (_) => Future<void>.error(failure);
    final service =
        WebViewVideoSourceService(controllerFactory: () => controller);
    addTearDown(service.dispose);

    await expectLater(
      service.resolve(_firstPage, useLegacyParser: false),
      throwsA(same(failure)),
    );
    expect(controller.hasParserListener, isFalse);
    expect(controller.unloads, 1);
    controller.onLoad = (_) {
      controller.emit(_secondVideo);
      return Future<void>.value();
    };
    expect((await service.resolve(_secondPage, useLegacyParser: false)).url,
        _secondVideo);
  });

  test('early parser error is handled while load is still pending', () async {
    final loadGate = Completer<void>();
    final failure = StateError('parser failed');
    final controller = _FakeWebviewController()
      ..onLoad = (_) => loadGate.future;
    final service =
        WebViewVideoSourceService(controllerFactory: () => controller);
    addTearDown(service.dispose);

    final resolving = service.resolve(_firstPage, useLegacyParser: false);
    final failed = expectLater(resolving, throwsA(same(failure)));
    await controller.firstLoadStarted.future;
    controller.emitError(failure);
    await _flushAsync();
    expect(controller.hasParserListener, isFalse);
    expect(controller.unloads, 0);
    loadGate.complete();
    await failed;
    expect(controller.unloads, 1);
  });

  test('closing parser stream fails without waiting for timeout', () async {
    final controller = _FakeWebviewController();
    final service =
        WebViewVideoSourceService(controllerFactory: () => controller);
    addTearDown(service.dispose);

    final resolving = service.resolve(_firstPage, useLegacyParser: false);
    final failed =
        expectLater(resolving, throwsA(isA<VideoSourceNotFoundException>()));
    await controller.firstLoadStarted.future;
    await controller.closeParser();
    await failed;
    expect(controller.hasParserListener, isFalse);
    expect(controller.unloads, 1);
  });

  test('initialization failure disposes failed controller and can retry',
      () async {
    final failure = StateError('init failed');
    final failedController = _FakeWebviewController()..initFailure = failure;
    final goodController = _FakeWebviewController();
    goodController.onLoad = (_) {
      goodController.emit(_secondVideo);
      return Future<void>.value();
    };
    final controllers = [failedController, goodController].iterator;
    final service = WebViewVideoSourceService(controllerFactory: () {
      expect(controllers.moveNext(), isTrue);
      return controllers.current;
    });
    addTearDown(service.dispose);

    await expectLater(
      service.resolve(_firstPage, useLegacyParser: false),
      throwsA(same(failure)),
    );
    expect(failedController.disposals, 1);
    expect(failedController.loads, isEmpty);
    expect(failedController.hasParserListener, isFalse);
    expect((await service.resolve(_secondPage, useLegacyParser: false)).url,
        _secondVideo);
  });

  test('dispose cancels pending load, drains serial work and closes logs',
      () async {
    final loadGate = Completer<void>();
    final controller = _FakeWebviewController()
      ..onLoad = (_) => loadGate.future;
    final service =
        WebViewVideoSourceService(controllerFactory: () => controller);
    final logs = <String>[];
    var logsClosed = false;
    final logSubscription =
        service.onLog.listen(logs.add, onDone: () => logsClosed = true);
    addTearDown(logSubscription.cancel);
    addTearDown(service.dispose);

    final resolving = service.resolve(_firstPage, useLegacyParser: false);
    final cancelled =
        expectLater(resolving, throwsA(isA<VideoSourceCancelledException>()));
    await controller.firstLoadStarted.future;
    controller.logEventController.add('load started');
    await _flushAsync();
    expect(logs, ['load started']);

    var disposed = false;
    final disposal = service.dispose()..then((_) => disposed = true);
    await _flushAsync();
    expect(controller.hasParserListener, isFalse);
    expect(disposed, isFalse);
    expect(controller.unloads, 0);
    controller.emit(_staleVideo);
    await expectLater(
      service.resolve(_secondPage, useLegacyParser: false),
      throwsA(isA<VideoSourceCancelledException>()),
    );
    loadGate.complete();
    await cancelled;
    await disposal;
    expect(controller.unloads, 1);
    expect(controller.disposals, 1);
    expect(controller.hasParserListener, isFalse);
    expect(controller.parserClosed, isTrue);
    expect(logsClosed, isTrue);
    expect(controller.loads.map((load) => load.url), [_firstPage]);
  });
}

class _FakeWebviewController extends VideoWebviewController<Object> {
  _FakeWebviewController() {
    _parser = StreamController<VideoParserEvent>.broadcast(
      sync: true,
      onListen: () => hasParserListener = true,
      onCancel: () => hasParserListener = false,
    );
  }

  late final StreamController<VideoParserEvent> _parser;
  final firstLoadStarted = Completer<void>();
  final loads = <({String url, bool useLegacyParser, int offset})>[];
  Future<void> Function(String url)? onLoad;
  Future<void> Function()? onUnload;
  Object? initFailure;
  int initializations = 0;
  int unloads = 0;
  int disposals = 0;
  bool hasParserListener = false;
  bool get parserClosed => _parser.isClosed;

  @override
  Stream<VideoParserEvent> get onVideoURLParser => _parser.stream;

  void emit(String url, {VideoSourceFormat format = VideoSourceFormat.auto}) =>
      _parser.add((url: url, offset: offset, format: format));

  void emitError(Object error) => _parser.addError(error, StackTrace.current);

  Future<void> closeParser() => _parser.close();

  @override
  Future<void> init() async {
    initializations++;
    if (initFailure != null) throw initFailure!;
  }

  @override
  Future<void> loadUrl(String url, bool useLegacyParser, {int offset = 0}) {
    expect(disposals, 0);
    this.offset = offset;
    loads.add((url: url, useLegacyParser: useLegacyParser, offset: offset));
    if (!firstLoadStarted.isCompleted) firstLoadStarted.complete();
    return onLoad?.call(url) ?? Future<void>.value();
  }

  @override
  Future<void> unloadPage() async {
    expect(hasParserListener, isFalse,
        reason:
            'No URL subscription may survive into unload or the next load.');
    unloads++;
    await onUnload?.call();
  }

  @override
  Future<void> dispose() async {
    disposals++;
    expect(hasParserListener, isFalse);
    await _parser.close();
    disposeEventControllers();
  }
}
