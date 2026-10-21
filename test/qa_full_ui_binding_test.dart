import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/video_source/video_source_service.dart';
import '../tools/qa/full_ui/video_source_binding.dart';

const _source = VideoSource(
    url: 'https://media.test/one.mp4', offset: 7, type: VideoSourceType.online);

class _Service implements IVideoSourceService {
  _Service(this.run, {this.close});
  final Future<VideoSource> Function(Duration) run;
  final Future<void> Function()? close;
  Duration? timeout;
  bool? legacy;
  int cancellations = 0;
  @override
  Future<VideoSource> resolve(String url,
      {required bool useLegacyParser,
      int offset = 0,
      Duration timeout = const Duration(seconds: 30)}) {
    this.timeout = timeout;
    legacy = useLegacyParser;
    return run(timeout);
  }

  @override
  void cancel() => cancellations++;
  @override
  Future<void> dispose() async => close?.call();
}

Future<VideoSource> _missing(Duration _) async =>
    throw const VideoSourceNotFoundException();

Future<VideoSource> _resolve(QaUiVideoSourceBinding binding,
        {Map<String, String> headers = const {'user-agent': 'one'},
        bool legacy = false}) =>
    binding.resolveWithHeaders('https://page.test/one',
        useLegacyParser: legacy,
        offset: 7,
        timeout: const Duration(seconds: 15),
        headers: headers);

void main() {
  test('each request freezes headers and creates fresh phase services',
      () async {
    final primary = <_Service>[];
    final seen = <Map<String, String>>[];
    final binding = QaUiVideoSourceBinding(
        gate: QaUiRetirementGate(),
        enabled: true,
        capabilityEligible: () => true,
        primaryFactory: () {
          final service = _Service(_missing);
          primary.add(service);
          return service;
        },
        fallbackFactory: (headers) {
          expect(
              () => headers['user-agent'] = 'mutated', throwsUnsupportedError);
          seen.add(headers);
          return _Service((_) async => _source);
        });
    final headers = {'user-agent': 'first', 'referer': 'https://page.test/'};
    final first = _resolve(binding, headers: headers);
    headers['user-agent'] = 'second';
    expect(await first, same(_source));
    expect(await _resolve(binding, headers: headers), same(_source));
    expect(seen.map((h) => h['user-agent']), ['first', 'second']);
    expect(primary, hasLength(2));
    expect(primary.map((p) => p.timeout),
        everyElement(const Duration(seconds: 10)));
    await binding.dispose();
  });

  for (final flags in [
    (false, true, false),
    (true, false, false),
    (true, true, true)
  ]) {
    test('disabled/ineligible/iframe-only $flags retains ordinary 15s',
        () async {
      final primary = _Service((_) async => _source);
      var fallbacks = 0;
      final binding = QaUiVideoSourceBinding(
          gate: QaUiRetirementGate(),
          enabled: flags.$1,
          capabilityEligible: () => flags.$2,
          primaryFactory: () => primary,
          fallbackFactory: (_) {
            fallbacks++;
            return _Service(_missing);
          });
      expect(await _resolve(binding, legacy: flags.$3), same(_source));
      expect(primary.timeout, const Duration(seconds: 15));
      expect(primary.legacy, flags.$3);
      expect(fallbacks, 0);
      await binding.dispose();
    });
  }

  test('interface call without paired headers cannot construct Gecko',
      () async {
    final primary = _Service((_) async => _source);
    final binding = QaUiVideoSourceBinding(
        gate: QaUiRetirementGate(),
        enabled: true,
        capabilityEligible: () => true,
        primaryFactory: () => primary,
        fallbackFactory: (_) => throw StateError('must not start'));
    expect(await binding.resolve('https://page.test', useLegacyParser: false),
        same(_source));
    expect(primary.timeout, const Duration(seconds: 15));
    await binding.dispose();
  });

  test('ordinary retirement gates another route and consumes QA deadline',
      () async {
    final gate = QaUiRetirementGate();
    final entered = Completer<void>(), release = Completer<void>();
    final old = QaUiVideoSourceBinding(
        gate: gate,
        enabled: false,
        capabilityEligible: () => false,
        primaryFactory: () => _Service((_) async => _source, close: () {
              entered.complete();
              return release.future;
            }),
        fallbackFactory: (_) => throw StateError('not used'));
    final before = old.resolve('https://page.test/old', useLegacyParser: true);
    final cancelled =
        expectLater(before, throwsA(isA<VideoSourceCancelledException>()));
    await entered.future;
    old.cancel();
    Duration? backup;
    var creations = 0;
    final next = QaUiVideoSourceBinding(
        gate: gate,
        enabled: true,
        capabilityEligible: () => true,
        totalBudget: const Duration(milliseconds: 500),
        primaryBudget: const Duration(milliseconds: 100),
        primaryFactory: () {
          creations++;
          return _Service(_missing);
        },
        fallbackFactory: (_) => _Service((budget) async {
              backup = budget;
              return _source;
            }));
    final following = _resolve(next);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(creations, 0); // no second engine before old retirement
    release.complete();
    await cancelled;
    expect(await following, same(_source));
    expect(backup, lessThan(const Duration(milliseconds: 400)));
    await old.dispose();
    await next.dispose();
  });

  test('expired queued QA request never gets a new engine or fresh 25s',
      () async {
    final gate = QaUiRetirementGate();
    final entered = Completer<void>(), release = Completer<void>();
    final old = QaUiVideoSourceBinding(
        gate: gate,
        enabled: false,
        capabilityEligible: () => false,
        primaryFactory: () => _Service((_) async => _source, close: () {
              entered.complete();
              return release.future;
            }),
        fallbackFactory: (_) => throw StateError('not used'));
    final before = old.resolve('https://page.test/old', useLegacyParser: false);
    final cancelled =
        expectLater(before, throwsA(isA<VideoSourceCancelledException>()));
    await entered.future;
    old.cancel();
    var creations = 0;
    final next = QaUiVideoSourceBinding(
        gate: gate,
        enabled: true,
        capabilityEligible: () => true,
        totalBudget: const Duration(milliseconds: 50),
        primaryFactory: () {
          creations++;
          return _Service(_missing);
        },
        fallbackFactory: (_) => throw StateError('not used'));
    final expired = expectLater(
        _resolve(next), throwsA(isA<VideoSourceTimeoutException>()));
    await Future<void>.delayed(const Duration(milliseconds: 90));
    release.complete();
    await cancelled;
    await expired;
    expect(creations, 0);
    await old.dispose();
    await next.dispose();
  });

  test('cancel during slow primary retirement cannot publish or fall back',
      () async {
    final entered = Completer<void>(), release = Completer<void>();
    var fallbacks = 0;
    final binding = QaUiVideoSourceBinding(
        gate: QaUiRetirementGate(),
        enabled: true,
        capabilityEligible: () => true,
        primaryFactory: () => _Service((_) async => _source, close: () {
              entered.complete();
              return release.future;
            }),
        fallbackFactory: (_) {
          fallbacks++;
          return _Service(_missing);
        });
    final cancelled = expectLater(
        _resolve(binding), throwsA(isA<VideoSourceCancelledException>()));
    await entered.future;
    binding.cancel();
    release.complete();
    await cancelled;
    await binding.dispose();
    expect(fallbacks, 0);
  });

  test('unconfirmed cleanup quarantines ordinary and QA routes', () async {
    final gate = QaUiRetirementGate();
    final old = QaUiVideoSourceBinding(
        gate: gate,
        enabled: false,
        capabilityEligible: () => false,
        primaryFactory: () => _Service((_) async => _source,
            close: () async => throw StateError('cleanup')),
        fallbackFactory: (_) => throw StateError('not used'));
    await expectLater(_resolve(old), throwsStateError);
    var starts = 0;
    final next = QaUiVideoSourceBinding(
        gate: gate,
        enabled: true,
        capabilityEligible: () => true,
        primaryFactory: () {
          starts++;
          return _Service((_) async => _source);
        },
        fallbackFactory: (_) => throw StateError('not used'));
    await expectLater(_resolve(next), throwsStateError);
    expect(starts, 0);
    await expectLater(old.dispose(), throwsStateError);
    await expectLater(next.dispose(), throwsStateError);
  });

  test('route dispose drains its own task, not a following route', () async {
    final gate = QaUiRetirementGate();
    final entered = Completer<void>(), release = Completer<void>();
    final nextStarted = Completer<void>(), nextMedia = Completer<VideoSource>();
    final old = QaUiVideoSourceBinding(
        gate: gate,
        enabled: false,
        capabilityEligible: () => false,
        primaryFactory: () => _Service((_) async => _source, close: () {
              entered.complete();
              return release.future;
            }),
        fallbackFactory: (_) => throw StateError('not used'));
    final cancelled = expectLater(
        _resolve(old), throwsA(isA<VideoSourceCancelledException>()));
    await entered.future;
    final disposal = old.dispose();
    final next = QaUiVideoSourceBinding(
        gate: gate,
        enabled: false,
        capabilityEligible: () => false,
        primaryFactory: () => _Service((_) {
              nextStarted.complete();
              return nextMedia.future;
            }),
        fallbackFactory: (_) => throw StateError('not used'));
    final following = _resolve(next);
    release.complete();
    await cancelled;
    await nextStarted.future;
    await disposal.timeout(const Duration(seconds: 1));
    nextMedia.complete(_source);
    expect(await following, same(_source));
    await next.dispose();
  });

  test('slow unconfirmed retirement blocks new route even after late close',
      () async {
    final gate = QaUiRetirementGate();
    final release = Completer<void>();
    final old = QaUiVideoSourceBinding(
      gate: gate,
      enabled: false,
      capabilityEligible: () => false,
      cleanupBudget: const Duration(milliseconds: 30),
      primaryFactory: () =>
          _Service((_) async => _source, close: () => release.future),
      fallbackFactory: (_) => throw StateError('not used'),
    );
    await expectLater(_resolve(old), throwsA(isA<TimeoutException>()));
    var starts = 0;
    final next = QaUiVideoSourceBinding(
      gate: gate,
      enabled: true,
      capabilityEligible: () => true,
      primaryFactory: () {
        starts++;
        return _Service((_) async => _source);
      },
      fallbackFactory: (_) => throw StateError('not used'),
    );
    release.complete();
    await expectLater(_resolve(next), throwsStateError);
    expect(starts, 0);
    await expectLater(old.dispose(), throwsStateError);
    await expectLater(next.dispose(), throwsStateError);
  });

  test('cancel queued route never constructs an ordinary or Gecko engine',
      () async {
    final gate = QaUiRetirementGate();
    final entered = Completer<void>(), release = Completer<void>();
    final old = QaUiVideoSourceBinding(
      gate: gate,
      enabled: false,
      capabilityEligible: () => false,
      primaryFactory: () => _Service((_) async => _source, close: () {
        entered.complete();
        return release.future;
      }),
      fallbackFactory: (_) => throw StateError('not used'),
    );
    final before = old.resolve('https://page.test/old', useLegacyParser: false);
    await entered.future;
    var starts = 0;
    final next = QaUiVideoSourceBinding(
      gate: gate,
      enabled: true,
      capabilityEligible: () => true,
      primaryFactory: () {
        starts++;
        return _Service((_) async => _source);
      },
      fallbackFactory: (_) => throw StateError('not used'),
    );
    final rejected = expectLater(
        _resolve(next), throwsA(isA<VideoSourceCancelledException>()));
    next.cancel();
    release.complete();
    expect(await before, same(_source));
    await rejected;
    await old.dispose();
    await next.dispose();
    expect(starts, 0);
  });
}
