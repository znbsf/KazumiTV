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
  test('historical service defaults remain primary 15s and shared 25s', () async {
    final service = QaAppFallbackService(
        primaryFactory: () => FakeService((_) async => source),
        fallbackFactory: () => FakeService(fail),
        enabled: true,
        eligible: true);
    expect(service.primaryBudget, const Duration(seconds: 15));
    expect(service.totalBudget, const Duration(seconds: 25));
    await service.dispose();
  });

  test('10s candidate accepts normal primary without constructing fallback',
      () async {
    var fallbackCount = 0;
    Duration? actualPrimaryBudget;
    final service = QaAppFallbackService(
        primaryFactory: () => FakeService((budget) async {
              actualPrimaryBudget = budget;
              return source;
            }),
        fallbackFactory: () {
          fallbackCount++;
          return FakeService(fail);
        },
        enabled: true,
        eligible: true,
        primaryBudget: const Duration(seconds: 10),
        totalBudget: const Duration(seconds: 25));
    expect(await service.resolve('https://page.test', useLegacyParser: false),
        same(source));
    expect(actualPrimaryBudget, const Duration(seconds: 10));
    expect(fallbackCount, 0);
    await service.dispose();
  });

  test('scaled 10/25 candidate leaves room that historical 15/25 cannot',
      () async {
    // Scale seconds by 20ms. Same total and same cold-engine work in both
    // runs; only primaryBudget differs. This proves scheduling, not site cause.
    for (final primaryMs in [300, 200]) {
      final latePrimary = Completer<VideoSource>();
      final events = <Map<String, Object?>>[];
      var fallbackCount = 0;
      Duration? backupBudget;
      final service = QaAppFallbackService(
          primaryFactory: () => FakeService((_) => latePrimary.future),
          fallbackFactory: () {
            fallbackCount++;
            return FakeService((budget) {
              backupBudget = budget;
              return Future<VideoSource>.delayed(
                  const Duration(milliseconds: 240), () => source);
            });
          },
          enabled: true,
          eligible: true,
          primaryBudget: Duration(milliseconds: primaryMs),
          totalBudget: const Duration(milliseconds: 500),
          onEvent: events.add);
      final request =
          service.resolve('https://page.test', useLegacyParser: false);
      if (primaryMs == 300) {
        await expectLater(request, throwsA(isA<VideoSourceTimeoutException>()));
        expect(backupBudget, lessThan(const Duration(milliseconds: 250)));
      } else {
        expect(await request, same(source));
        expect(backupBudget, greaterThan(const Duration(milliseconds: 250)));
      }
      latePrimary.complete(source);
      await service.dispose();
      expect(fallbackCount, 1);
      expect(events.where((x) => x['phase'] == 'primary' && x['stage'] == 'accepted'), isEmpty);
      expect(events.indexWhere((x) => x['phase'] == 'primary' && x['stage'] == 'retired'),
          lessThan(events.indexWhere((x) => x['phase'] == 'fallback' && x['stage'] == 'started')));
      expect(events.where((x) => x['stage'] == 'accepted'),
          hasLength(primaryMs == 200 ? 1 : 0));
    }
  });

  test('scaled 10/25 shared deadline stops one ignoring fallback and late media',
      () async {
    final latePrimary = Completer<VideoSource>();
    final lateBackup = Completer<VideoSource>();
    final events = <Map<String, Object?>>[];
    var fallbackCount = 0;
    Duration? backupBudget;
    final service = QaAppFallbackService(
        primaryFactory: () => FakeService((_) => latePrimary.future),
        fallbackFactory: () {
          fallbackCount++;
          return FakeService((budget) {
            backupBudget = budget;
            return lateBackup.future;
          });
        },
        enabled: true,
        eligible: true,
        primaryBudget: const Duration(milliseconds: 40),
        totalBudget: const Duration(milliseconds: 100),
        onEvent: events.add);
    final clock = Stopwatch()..start();
    await expectLater(service.resolve('https://page.test', useLegacyParser: false),
        throwsA(isA<VideoSourceTimeoutException>()));
    expect(clock.elapsedMilliseconds, lessThan(600));
    expect(backupBudget, lessThanOrEqualTo(const Duration(milliseconds: 60)));
    expect(fallbackCount, 1);
    latePrimary.complete(source);
    lateBackup.complete(source);
    await service.dispose();
    expect(events.where((x) => x['stage'] == 'accepted'), isEmpty);
  });

  for (final switchEpisode in [false, true]) {
    test('candidate timeout retirement rejects ${switchEpisode ? 'switch' : 'cancel'} before fallback',
        () async {
      final retiring = Completer<void>(), released = Completer<void>();
      final late = Completer<VideoSource>();
      final events = <Map<String, Object?>>[];
      var primaryCount = 0, fallbackCount = 0;
      final service = QaAppFallbackService(
          primaryFactory: () => ++primaryCount == 1
              ? FakeService((_) => late.future, close: () {
                  retiring.complete();
                  return released.future;
                })
              : FakeService((_) async => source),
          fallbackFactory: () {
            fallbackCount++;
            return FakeService(fail);
          },
          enabled: true,
          eligible: true,
          primaryBudget: const Duration(milliseconds: 40),
          totalBudget: const Duration(milliseconds: 100),
          onEvent: events.add);
      final old = expectLater(
          service.resolve('https://page.test/old', useLegacyParser: false),
          throwsA(isA<VideoSourceCancelledException>()));
      await retiring.future;
      expect(fallbackCount, 0);
      Future<VideoSource>? next;
      if (switchEpisode) {
        next = service.resolve('https://page.test/new', useLegacyParser: false);
      } else {
        service.cancel();
      }
      released.complete();
      await old;
      if (next != null) expect(await next, same(source));
      late.complete(source);
      await service.dispose();
      expect(fallbackCount, 0);
      expect(events.where((x) => x['generation'] == 1 && x['stage'] == 'accepted'), isEmpty);
    });
  }

  test('candidate slow unconfirmed retirement never starts fallback', () async {
    final released = Completer<void>(), late = Completer<VideoSource>();
    var fallbackCount = 0;
    final events = <Map<String, Object?>>[];
    final service = QaAppFallbackService(
        primaryFactory: () => FakeService((_) => late.future, close: () => released.future),
        fallbackFactory: () {
          fallbackCount++;
          return FakeService(fail);
        },
        enabled: true,
        eligible: true,
        primaryBudget: const Duration(milliseconds: 40),
        totalBudget: const Duration(milliseconds: 100),
        cleanupBudget: const Duration(milliseconds: 120),
        onEvent: events.add);
    await expectLater(service.resolve('https://page.test', useLegacyParser: false),
        throwsA(isA<TimeoutException>()));
    expect(fallbackCount, 0);
    expect(events.where((x) => x['stage'] == 'cleanup_unconfirmed'), hasLength(1));
    released.complete();
    late.complete(source);
    await expectLater(service.dispose(), throwsStateError);
    expect(events.where((x) => x['stage'] == 'accepted'), isEmpty);
  });

  for (final fallback in [false, true]) {
    for (final action in ['cancel', 'switch', 'dispose']) {
      test(
          '${fallback ? 'fallback' : 'primary'} retirement rejects $action before publication',
          () async {
        final entered = Completer<void>(), retired = Completer<void>();
        var primaryCalls = 0;
        final events = <Map<String, Object?>>[];
        Future<void> close() {
          entered.complete();
          return retired.future;
        }

        final service = QaAppFallbackService(
            primaryFactory: () {
              primaryCalls++;
              if (primaryCalls > 1) return FakeService((_) async => source);
              return fallback
                  ? FakeService(fail)
                  : FakeService((_) async => source, close: close);
            },
            fallbackFactory: () =>
                FakeService((_) async => source, close: close),
            enabled: true,
            eligible: true,
            onEvent: events.add);
        final first =
            service.resolve('https://page.test/old', useLegacyParser: false);
        final rejected =
            expectLater(first, throwsA(isA<VideoSourceCancelledException>()));
        await entered.future;
        Future<VideoSource>? next;
        Future<void>? disposed;
        if (action == 'cancel') {
          service.cancel();
        }
        if (action == 'switch') {
          next =
              service.resolve('https://page.test/new', useLegacyParser: false);
        }
        if (action == 'dispose') {
          disposed = service.dispose();
        }
        retired.complete();
        await rejected;
        if (next != null) expect(await next, same(source));
        await disposed;
        if (action != 'dispose') await service.dispose();
        expect(
            events
                .where((x) => x['generation'] == 1 && x['stage'] == 'accepted'),
            isEmpty);
      });
    }
  }

  test(
      'primary phase deadline leaves budget even when the engine ignores timeout',
      () async {
    var fallbackCount = 0;
    Duration? backupBudget;
    final service = QaAppFallbackService(
        primaryFactory: () =>
            FakeService((_) => Completer<VideoSource>().future),
        fallbackFactory: () {
          fallbackCount++;
          return FakeService((timeout) async {
            backupBudget = timeout;
            return source;
          });
        },
        enabled: true,
        eligible: true,
        primaryBudget: const Duration(milliseconds: 30),
        totalBudget: const Duration(seconds: 2));
    try {
      expect(await service.resolve('https://page.test', useLegacyParser: false),
          same(source));
      expect(fallbackCount, 1);
      expect(backupBudget, greaterThan(Duration.zero));
      expect(backupBudget, lessThan(const Duration(seconds: 2)));
    } finally {
      await service.dispose();
    }
  });

  test('successful retirement preserves deadline and accepts current media',
      () async {
    final entered = Completer<void>(), retired = Completer<void>();
    final events = <Map<String, Object?>>[];
    final service = QaAppFallbackService(
        primaryFactory: () => FakeService((_) async => source, close: () {
              entered.complete();
              return retired.future;
            }),
        fallbackFactory: () => FakeService(fail),
        enabled: true,
        eligible: true,
        onEvent: events.add);
    final request =
        service.resolve('https://page.test', useLegacyParser: false);
    await entered.future;
    retired.complete();
    expect(await request, same(source));
    expect(events.where((x) => x['stage'] == 'accepted'), hasLength(1));
    expect(events.last['stage'], 'accepted');
    await service.dispose();
  });

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
