import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/video_source/video_source_service.dart';
import '../tools/qa/source_batch/app_fallback_service.dart';

const source = VideoSource(
    url: 'https://media.test/file.mp4',
    offset: 9,
    type: VideoSourceType.online);

class FakeService implements IVideoSourceService {
  FakeService(this.run, {this.close});
  final Future<VideoSource> Function(Duration timeout) run;
  final Future<void> Function()? close;
  int cancellations = 0;
  String? url;
  int? offset;
  @override
  Future<VideoSource> resolve(String episodeUrl,
      {required bool useLegacyParser,
      int offset = 0,
      Duration timeout = const Duration(seconds: 30)}) {
    url = episodeUrl;
    this.offset = offset;
    return run(timeout);
  }

  @override
  void cancel() {
    cancellations++;
  }

  @override
  Future<void> dispose() async {
    await close?.call();
  }
}

Future<VideoSource> fail(Duration _) async =>
    throw const VideoSourceTimeoutException(Duration(seconds: 15));

void main() {
  test('primary success never constructs fallback; telemetry cannot break it',
      () async {
    var fallbackCount = 0;
    final service = QaAppFallbackService(
        primaryFactory: () => FakeService((_) async => source),
        fallbackFactory: () {
          fallbackCount++;
          return FakeService(fail);
        },
        enabled: true,
        eligible: true,
        onEvent: (_) => throw StateError('sink'));
    expect(await service.resolve('https://page.test', useLegacyParser: false),
        same(source));
    expect(fallbackCount, 0);
    await service.dispose();
  });

  test(
      'fallback waits for primary retirement and preserves input and remaining deadline',
      () async {
    final retired = Completer<void>();
    var fallbackCount = 0;
    Duration? remaining;
    final backup = FakeService((timeout) async {
      remaining = timeout;
      return source;
    });
    final events = <Map<String, Object?>>[];
    final service = QaAppFallbackService(
        primaryFactory: () => FakeService(fail, close: () => retired.future),
        fallbackFactory: () {
          fallbackCount++;
          return backup;
        },
        enabled: true,
        eligible: true,
        onEvent: events.add);
    final request = service.resolve('https://page.test/episode',
        useLegacyParser: false, offset: 9);
    await Future<void>.delayed(Duration.zero);
    expect(fallbackCount, 0);
    retired.complete();
    expect(await request, same(source));
    expect(fallbackCount, 1);
    expect(backup.url, 'https://page.test/episode');
    expect(backup.offset, 9);
    expect(remaining, lessThanOrEqualTo(const Duration(seconds: 25)));
    expect(
        events.indexWhere(
            (x) => x['phase'] == 'primary' && x['stage'] == 'retired'),
        lessThan(events.indexWhere(
            (x) => x['phase'] == 'fallback' && x['stage'] == 'started')));
    await service.dispose();
  });

  test(
      'disabled, modern-capability or iframe-only policy never constructs fallback',
      () async {
    for (final flags in [
      (false, true, false),
      (true, false, false),
      (true, true, true)
    ]) {
      var count = 0;
      final service = QaAppFallbackService(
          primaryFactory: () => FakeService(fail),
          fallbackFactory: () {
            count++;
            return FakeService(fail);
          },
          enabled: flags.$1,
          eligible: flags.$2);
      await expectLater(
          service.resolve('https://page.test', useLegacyParser: flags.$3),
          throwsA(isA<VideoSourceTimeoutException>()));
      expect(count, 0);
      await service.dispose();
    }
  });

  test('non-parser error never falls back; fallback failure is not retried',
      () async {
    for (final parserFailure in [false, true]) {
      var count = 0;
      final service = QaAppFallbackService(
          primaryFactory: () => FakeService(
              parserFailure ? fail : (_) async => throw StateError('native')),
          fallbackFactory: () {
            count++;
            return FakeService(fail);
          },
          enabled: true,
          eligible: true);
      await expectLater(
          service.resolve('https://page.test', useLegacyParser: false),
          throwsA(parserFailure
              ? isA<VideoSourceTimeoutException>()
              : isA<StateError>()));
      expect(count, parserFailure ? 1 : 0);
      await service.dispose();
    }
  });

  test('cancelled primary rejects late result and does not start fallback',
      () async {
    final late = Completer<VideoSource>();
    var count = 0;
    final service = QaAppFallbackService(
        primaryFactory: () => FakeService((_) => late.future),
        fallbackFactory: () {
          count++;
          return FakeService(fail);
        },
        enabled: true,
        eligible: true);
    final check = expectLater(
        service.resolve('https://page.test', useLegacyParser: false),
        throwsA(isA<VideoSourceCancelledException>()));
    await Future<void>.delayed(Duration.zero);
    service.cancel();
    await check;
    late.complete(source);
    await service.dispose();
    expect(count, 0);
  });

  test('switching episodes rejects old result before the new primary runs',
      () async {
    final late = Completer<VideoSource>();
    var primaryCount = 0, fallbackCount = 0;
    final service = QaAppFallbackService(
        primaryFactory: () => FakeService(
            (_) => ++primaryCount == 1 ? late.future : Future.value(source)),
        fallbackFactory: () {
          fallbackCount++;
          return FakeService(fail);
        },
        enabled: true,
        eligible: true);
    final old = expectLater(
        service.resolve('https://page.test/old', useLegacyParser: false),
        throwsA(isA<VideoSourceCancelledException>()));
    await Future<void>.delayed(Duration.zero);
    final current =
        service.resolve('https://page.test/new', useLegacyParser: false);
    await old;
    expect(await current, same(source));
    late.complete(source);
    expect(primaryCount, 2);
    expect(fallbackCount, 0);
    await service.dispose();
  });

  test('failed cleanup stops switching and remains unconfirmed on disposal',
      () async {
    var fallbackCount = 0;
    final service = QaAppFallbackService(
        primaryFactory: () =>
            FakeService(fail, close: () async => throw StateError('cleanup')),
        fallbackFactory: () {
          fallbackCount++;
          return FakeService(fail);
        },
        enabled: true,
        eligible: true);
    await expectLater(
        service.resolve('https://page.test', useLegacyParser: false),
        throwsStateError);
    expect(fallbackCount, 0);
    await expectLater(service.dispose(), throwsStateError);
  });

  test('global deadline expires with no renewed fallback budget', () async {
    var fallbackCount = 0;
    final service = QaAppFallbackService(
        primaryFactory: () =>
            FakeService((_) => Completer<VideoSource>().future),
        fallbackFactory: () {
          fallbackCount++;
          return FakeService(fail);
        },
        enabled: true,
        eligible: true,
        totalBudget: const Duration(milliseconds: 20));
    await expectLater(
        service.resolve('https://page.test', useLegacyParser: false),
        throwsA(isA<VideoSourceTimeoutException>()));
    expect(fallbackCount, 0);
    await service.dispose();
  });

  test('cancelling fallback never accepts its late media', () async {
    final started = Completer<void>(), late = Completer<VideoSource>();
    final service = QaAppFallbackService(
        primaryFactory: () => FakeService(fail),
        fallbackFactory: () => FakeService((_) {
              started.complete();
              return late.future;
            }),
        enabled: true,
        eligible: true);
    final check = expectLater(
        service.resolve('https://page.test', useLegacyParser: false),
        throwsA(isA<VideoSourceCancelledException>()));
    await started.future;
    service.cancel();
    await check;
    late.complete(source);
    await service.dispose();
  });
}
