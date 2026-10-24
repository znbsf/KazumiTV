import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/webview/video/video_webview_controller.dart';
import 'package:kazumi/services/video_source/webview_video_source_service.dart';
import 'package:kazumi/services/video_source/video_source_service.dart';
import '../tools/qa/source_batch/console_hints.dart';

Map<String, dynamic> config() => {
      'console_hint_observer': true,
      'id': qaConsoleCaseId,
      'group': 'console-hints',
      'engine': 'app',
      'source_key': 'mgnacg',
      'keyword': '学生会也有洞',
      'names': ['学生会也有洞！'],
      'rule': <String, dynamic>{},
      'rule_variant': 'effective',
      'repeat': 0,
      'road': 0,
      'episode': 1,
      'expected_episode_page_sha256': qaConsolePageSha,
      'expected_episode_label': '第2话',
    };
Map<String, Object?> rule() => {
      'name': 'mgnacg',
      'version': '1.2',
      'api': '9',
      'effective_sha256': qaConsoleRuleSha,
      'variant': 'effective',
      'overlay': false
    };
Map<String, dynamic> environment() => {
      'sdk': 28,
      'webview': 'com.android.webview/66.0.3359.158',
      'package': 'com.znbsf.kazumi.fluttertv.parserqa'
    };

class PrivateError implements Exception {
  static int stringifications = 0;
  @override
  String toString() {
    stringifications++;
    throw StateError('PRIVATE_SENTINEL');
  }
}

class HostileStream extends Stream<String> {
  void Function(String)? data;
  Function? error;
  void Function()? done;
  String? initial;
  bool throwsOnListen = false, throwsOnCancel = false;
  int listens = 0, cancels = 0;
  Completer<void>? cancelGate;
  @override
  StreamSubscription<String> listen(void Function(String)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    listens++;
    if (throwsOnListen) throw PrivateError();
    data = onData;
    error = onError;
    done = onDone;
    if (initial != null) {
      data?.call(initial!); // Deliberately emits before listen returns.
    }
    return HostileSubscription(this);
  }
}

class HostileSubscription implements StreamSubscription<String> {
  HostileSubscription(this.stream);
  final HostileStream stream;
  @override
  Future<void> cancel() async {
    stream.cancels++;
    if (stream.throwsOnCancel) throw PrivateError();
    await stream.cancelGate?.future;
  }

  @override
  void onData(void Function(String)? h) {
    stream.data = h;
  }

  @override
  void onError(Function? h) {
    stream.error = h;
  }

  @override
  void onDone(void Function()? h) {
    stream.done = h;
  }

  @override
  void pause([Future<void>? resumeSignal]) {}
  @override
  void resume() {}
  @override
  bool get isPaused => false;
  @override
  Future<E> asFuture<E>([E? futureValue]) => Future<E>.value(futureValue as E);
}

class FakeController extends VideoWebviewController<Object> {
  FakeController(
      {this.logs,
      this.initial =
          'Console [ERROR]: Uncaught SyntaxError: PRIVATE_SENTINEL'});
  final Stream<String>? logs;
  final String initial;
  int inits = 0, loads = 0, disposals = 0;
  @override
  Stream<String> get onLog => logs ?? super.onLog;
  @override
  Future<void> init() async {
    inits++;
    logEventController.add(initial);
  }

  @override
  Future<void> loadUrl(String url, bool useLegacyParser,
      {int offset = 0}) async {
    loads++;
    notifyVideoSourceResolved(
        'https://unit.invalid/fake.mp4'); // In-memory event, never fetched.
  }

  @override
  Future<void> unloadPage() async {}
  @override
  Future<void> dispose() async {
    disposals++;
    disposeEventControllers();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => PrivateError.stringifications = 0);

  test(
      'strict fixed opt-in rejects every other binding before reading a log stream',
      () async {
    expect(qaConsoleRequested({}), false);
    expect(qaConsoleRequested({'console_hint_observer': false}), false);
    expect(() => qaConsoleRequested({'console_hint_observer': 'true'}),
        throwsFormatException);
    var reads = 0;
    final stream = HostileStream();
    QaConsoleHintObserver? create(Map<String, dynamic> c,
            Map<String, Object?> r, Map<String, dynamic> e) =>
        createBoundQaConsoleObserver(
            config: c,
            rule: r,
            environment: e,
            logs: () {
              reads++;
              return stream;
            },
            isCurrent: () => true,
            onChallengeHint: () {},
            onUnavailable: () {});
    for (final patch in <Map<String, dynamic>>[
      {'console_hint_observer': false},
      {'id': 'other'},
      {'source_key': 'another'},
      {'expected_episode_page_sha256': '0' * 64},
      {'expected_episode_label': '第1话'},
      {'episode': 0},
      {
        'names': ['另一个作品']
      },
      {'app_gecko_fallback': true},
      {'observe_media_root': true},
      {'observe_playback_seconds': 10},
      {'selection_only': true},
      {'rule_variant': 'base'},
      {'repeat': 1},
      {'rule': null},
      {'url': 'PRIVATE_SENTINEL'},
    ]) {
      expect(create({...config(), ...patch}, rule(), environment()), isNull);
    }
    for (final patch in <Map<String, Object?>>[
      {'name': 'another'},
      {'version': '1.3'},
      {'api': '4'},
      {'effective_sha256': '0' * 64},
      {'overlay': true},
      {'variant': 'base'}
    ]) {
      expect(create(config(), {...rule(), ...patch}, environment()), isNull);
    }
    expect(create(config(), rule(), {...environment(), 'sdk': 36}), isNull);
    expect(create(config(), rule(), {...environment(), 'package': 'formal'}),
        isNull);
    expect(reads, 0);
    expect(stream.listens, 0);
    final observer = create(config(), rule(), environment());
    expect(observer, isNotNull);
    expect(reads, 1);
    expect(stream.listens, 1);
    expect(await observer!.stop(), true);
  });

  test('only known Console prefixes produce fixed hints and never raw text',
      () {
    final counter = QaConsoleHintCounter();
    const signed = 'https://private.invalid/PRIVATE_SENTINEL?sign=TOKEN_SECRET';
    for (final text in [
      'started loading: $signed',
      'LogBridge Cookie: TOKEN_SECRET',
      'Console [ERROR]: Uncaught SyntaxError: fake $signed\n at PRIVATE_SENTINEL',
      'Console [ERROR]: ReferenceError: fake $signed',
      'Console [WARNING]: Uncaught (in promise) TypeError: fake Cookie: TOKEN_SECRET',
      'Console [ERROR]: Access to $signed blocked by CORS policy',
      'Console [ERROR]: Refused fake due to Content Security Policy $signed',
      'Console [WARNING]: Mixed Content: fake $signed',
      'Console [ERROR]: Failed $signed net::ERR_BLOCKED_BY_CLIENT',
      'Console [LOG]: ordinary PRIVATE_SENTINEL',
    ]) {
      counter.accept(text);
    }
    final result = counter.snapshot();
    final counts = result['counts'] as Map;
    for (final category in [
      'syntax',
      'reference',
      'type',
      'cors',
      'csp',
      'mixedContent',
      'blockedResource',
      'unclassified'
    ]) {
      expect(counts[category], 1);
    }
    expect(result['accepted_records'], 8);
    expect(result['hints_only'], true);
    expect(result['console_authenticity_verified'], false);
    final encoded = jsonEncode(result);
    for (final value in [
      signed,
      'PRIVATE_SENTINEL',
      'TOKEN_SECRET',
      'Cookie',
      'https://',
      ' at '
    ]) {
      expect(encoded, isNot(contains(value)));
    }
  });

  test(
      'multi-line stacks, fake exceptions, URL and credential lines cannot become original error evidence',
      () {
    final c = QaConsoleHintCounter();
    for (final raw in [
      'Console [ERROR]: FakeException: PRIVATE_SENTINEL\nUncaught TypeError: SECRET',
      'Console [ERROR]: https://private.invalid/TypeError:SECRET?sign=PRIVATE_SENTINEL',
      'Console [ERROR]: Cookie: captcha=PRIVATE_SENTINEL\nAuthorization: Bearer SECRET',
      'Console [UNKNOWN]: Uncaught SyntaxError: PRIVATE_SENTINEL'
    ]) {
      c.accept(raw);
    }
    final x = c.snapshot();
    expect((x['counts'] as Map)['unclassified'], 3);
    expect((x['counts'] as Map)['type'], 0);
    expect(x['challengeHint'], false);
    expect(jsonEncode(x), isNot(contains('PRIVATE_SENTINEL')));
  });

  test('80 record cap seals input and overflow only retains the fixed boolean',
      () {
    final c = QaConsoleHintCounter();
    for (var i = 0; i < 80; i++) {
      c.accept('Console [ERROR]: TypeError: PRIVATE_SENTINEL');
    }
    expect(c.accept('Console [ERROR]: TypeError: SECRET'), QaConsoleStop.quota);
    c.accept('Console [ERROR]: captcha SECRET');
    final x = c.snapshot();
    expect(x['accepted_records'], 80);
    expect(x['overflow'], true);
    expect(x['challengeHint'], false);
    expect((x['counts'] as Map)['type'], 80);
    expect(jsonEncode(x), isNot(contains('SECRET')));
  });

  test('8192 code units and cumulative UTF8 bytes have separate real limits',
      () {
    const prefix = 'Console [LOG]: ';
    final c = QaConsoleHintCounter();
    c.accept(prefix + 'x' * (8192 - prefix.length));
    expect(c.snapshot()['accepted_records'], 1);
    expect(
        c.accept(prefix + 'x' * (8193 - prefix.length)), QaConsoleStop.quota);
    expect(c.snapshot()['accepted_records'], 1);
    final unicode = QaConsoleHintCounter();
    for (var i = 0; i < 80; i++) {
      if (unicode.accept(prefix + '界' * 2800) != null) break;
    }
    final x = unicode.snapshot();
    expect(x['overflow'], true);
    expect(x['accepted_records'] as int, lessThan(80));
    expect(x['accepted_utf8_bytes'] as int, lessThanOrEqualTo(256 * 1024));
    final ignored = QaConsoleHintCounter()
      ..accept('https://PRIVATE_SENTINEL/${'x' * 90000}');
    expect(ignored.snapshot()['accepted_records'], 0);
    expect(ignored.snapshot()['overflow'], false);
  });

  test(
      'stop awaits actual cancellation and late callbacks cannot mutate the snapshot',
      () async {
    final stream = HostileStream()..cancelGate = Completer<void>();
    final o = QaConsoleHintObserver(
        isCurrent: () => true, onChallengeHint: () {}, onUnavailable: () {});
    o.attach(() => stream);
    stream.data?.call('Console [ERROR]: SyntaxError: PRIVATE_SENTINEL');
    var finished = false;
    final close = o.stop(QaConsoleStop.cancelled).then((v) {
      finished = true;
      return v;
    });
    await Future<void>.delayed(Duration.zero);
    expect(finished, false);
    stream.data?.call('Console [ERROR]: TypeError: PRIVATE_SENTINEL');
    stream.cancelGate!.complete();
    expect(await close, true);
    expect(stream.cancels, 1);
    final before = jsonEncode(o.snapshot());
    stream.data?.call('Console [ERROR]: captcha PRIVATE_SENTINEL');
    Function.apply(stream.error!, [PrivateError(), StackTrace.current]);
    stream.done?.call();
    expect(jsonEncode(o.snapshot()), before);
    expect(PrivateError.stringifications, 0);
    (o.snapshot()['counts'] as Map)['syntax'] = 99;
    expect((o.snapshot()['counts'] as Map)['syntax'], 1);
  });

  test(
      'synchronous challenge during listen seals immediately and is pending hint, never proof',
      () async {
    final stream = HostileStream()
      ..initial = 'Console [ERROR]: verify you are human PRIVATE_SENTINEL';
    var hints = 0;
    final o = QaConsoleHintObserver(
        isCurrent: () => true,
        onChallengeHint: () {
          hints++;
        },
        onUnavailable: () {});
    o.attach(() => stream);
    expect(await o.stop(), true);
    expect(hints, 1);
    expect(stream.cancels, 1);
    expect(o.snapshot()['challengeHint'], true);
    expect(o.snapshot()['stop_reason'], 'challengeHint');
    expect(o.snapshot()['console_authenticity_verified'], false);
    stream.data?.call('Console [ERROR]: TypeError: SECRET');
    expect(o.snapshot()['accepted_records'], 1);
    expect(jsonEncode(o.snapshot()), isNot(contains('PRIVATE_SENTINEL')));
  });

  test('stop before attach or lost attribution never reads logs', () async {
    var reads = 0;
    final o = QaConsoleHintObserver(
        isCurrent: () => true, onChallengeHint: () {}, onUnavailable: () {});
    expect(await o.stop(QaConsoleStop.cancelled), true);
    expect(o.attach(() {
      reads++;
      return const Stream<String>.empty();
    }), false);
    final lost = QaConsoleHintObserver(
        isCurrent: () => false, onChallengeHint: () {}, onUnavailable: () {});
    expect(lost.attach(() {
      reads++;
      return const Stream<String>.empty();
    }), false);
    expect(await lost.stop(), true);
    expect(reads, 0);
    expect(lost.snapshot()['subscription_cleanup'], 'not_created');
  });

  test(
      'stream constructor/error/cancel exceptions are not stringified or sent to any network',
      () async {
    var clients = 0;
    await HttpOverrides.runZoned(() async {
      for (final mode in ['listen', 'error', 'cancel']) {
        final stream = HostileStream()
          ..throwsOnListen = mode == 'listen'
          ..throwsOnCancel = mode == 'cancel';
        var unavailable = 0;
        final o = QaConsoleHintObserver(
            isCurrent: () => true,
            onChallengeHint: () {},
            onUnavailable: () {
              unavailable++;
            });
        o.attach(() => stream);
        if (mode == 'error') {
          Function.apply(stream.error!, [PrivateError(), StackTrace.current]);
        }
        expect(await o.stop(), mode != 'cancel');
        expect(unavailable, mode == 'cancel' ? 0 : 1);
        expect(jsonEncode(o.snapshot()), isNot(contains('PRIVATE_SENTINEL')));
      }
    }, createHttpClient: (_) {
      clients++;
      throw StateError('network_must_not_be_constructed');
    });
    expect(clients, 0);
    expect(PrivateError.stringifications, 0);
  });

  test(
      'actual source service observes init console before init and resolution finish cancels it',
      () async {
    final controller = FakeController();
    QaConsoleHintObserver? observer;
    final service = WebViewVideoSourceService(
        diagnosticSink: (_) {},
        controllerFactory: () {
          observer = createBoundQaConsoleObserver(
              config: config(),
              rule: rule(),
              environment: environment(),
              logs: () => controller.onLog,
              isCurrent: () => true,
              onChallengeHint: () {},
              onUnavailable: () {});
          return controller;
        });
    try {
      await service.resolve('https://unit.invalid/page',
          useLegacyParser: false);
    } finally {
      expect(await observer!.stop(), true);
      await service.dispose();
    }
    expect(controller.inits, 1);
    expect(controller.loads, 1);
    expect(controller.disposals, 1);
    expect((observer!.snapshot()['counts'] as Map)['syntax'], 1);
    expect(observer!.snapshot()['subscription_cleanup'], 'confirmed');
  });

  test(
      'failed log construction cancels the source before page loading and adds no request',
      () async {
    final bad = HostileStream()..throwsOnListen = true;
    final controller = FakeController(logs: bad);
    QaConsoleHintObserver? observer;
    late final WebViewVideoSourceService service;
    service = WebViewVideoSourceService(
        diagnosticSink: (_) {},
        controllerFactory: () {
          observer = createBoundQaConsoleObserver(
              config: config(),
              rule: rule(),
              environment: environment(),
              logs: () => controller.onLog,
              isCurrent: () => true,
              onChallengeHint: () {
                service.cancel();
              },
              onUnavailable: () {
                service.cancel();
              });
          return controller;
        });
    await expectLater(
        service.resolve('https://unit.invalid/page', useLegacyParser: false),
        throwsA(isA<VideoSourceCancelledException>()));
    expect(await observer!.stop(), true);
    await service.dispose();
    expect(controller.loads, 0);
    expect(PrivateError.stringifications, 0);
  });
}
