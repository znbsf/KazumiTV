import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import '../tools/qa/full_ui/main.dart'
    show
        qaFullUiProfileAllowed,
        readQaFullUiCapability,
        requestQaFullUiRuntimeWarmup;
import '../tools/qa/source_batch/gecko_controller.dart' show qaChannel;

const _package = 'com.znbsf.kazumi.fluttertv.parserqa';
const _native = <Object?, Object?>{
  'package': _package,
  'activity': 'com.example.kazumi.ParserQaActivity',
  'debug': true,
  'full_ui': true,
  'tv': true,
  'offline': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(qaChannel, null));
  bool allowed(
          {bool debug = true,
          bool android = true,
          bool enabled = true,
          bool offline = false,
          String? flavor = 'parserQa',
          String package = _package,
          Map<Object?, Object?> native = _native}) =>
      qaFullUiProfileAllowed(
          debug: debug,
          android: android,
          dartEnabled: enabled,
          dartOffline: offline,
          flavor: flavor,
          packageName: package,
          native: native);

  test('only paired parserQa debug/full UI/TV/native Activity profile opts in',
      () {
    expect(allowed(), isTrue);
    expect(allowed(debug: false), isFalse);
    expect(allowed(android: false), isFalse);
    expect(allowed(enabled: false), isFalse);
    expect(allowed(offline: true), isFalse);
    expect(allowed(flavor: 'tv'), isFalse);
    expect(allowed(flavor: 'parserQaOffline'), isFalse);
    expect(allowed(package: 'com.znbsf.kazumi.fluttertv'), isFalse);
    expect(allowed(native: const {}), isFalse);
    for (final entry in <Object?, Object?>{
      'package': 'other',
      'activity': 'com.example.kazumi.MainActivity',
      'debug': false,
      'full_ui': false,
      'tv': false,
      'offline': true,
    }.entries) {
      expect(allowed(native: {..._native, entry.key: entry.value}), isFalse);
    }
    expect(allowed(native: {..._native, 'full_ui': 'true'}), isFalse);
  });

  test('ordinary TV identity remains; parserQa needs explicit paired override',
      () {
    expect(TvMode.enabledForBuild(android: true, flavor: 'tv'), isTrue);
    expect(TvMode.enabledForBuild(android: true, flavor: 'parserQa'), isFalse);
    expect(
        TvMode.enabledForBuild(
            android: true, flavor: 'parserQa', parserQaFullUi: true),
        isTrue);
    expect(
        TvMode.enabledForBuild(
            android: true, flavor: 'parserQaOffline', parserQaFullUi: true),
        isFalse);
    expect(
        TvMode.enabledForBuild(
            android: false, flavor: 'parserQa', parserQaFullUi: true),
        isFalse);
    expect(
        TvMode.enabledForBuild(
            android: true, flavor: null, parserQaFullUi: true),
        isFalse);
  });

  test('warmed engine waits for one positive native attachment without polling',
      () async {
    var reads = 0;
    messenger.setMockMethodCallHandler(qaChannel, (call) async {
      reads++;
      throw MissingPluginException();
    });
    final pending = readQaFullUiCapability();
    await Future<void>.delayed(Duration.zero);
    final delivered = Completer<void>();
    await messenger.handlePlatformMessage(
        qaChannel.name,
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('qaUiReady', _native)),
        (_) => delivered.complete());
    await delivered.future;
    expect(await pending, _native);
    expect(reads, 1);
  });

  test('headless missing native Activity times out without opt-in', () async {
    messenger.setMockMethodCallHandler(
        qaChannel, (_) async => throw MissingPluginException());
    await expectLater(
        readQaFullUiCapability(timeout: const Duration(milliseconds: 20)),
        throwsA(isA<TimeoutException>()));
  });

  test('explicit native profile mismatch is returned immediately and rejected',
      () async {
    var reads = 0;
    final wrong = {..._native, 'full_ui': false};
    messenger.setMockMethodCallHandler(qaChannel, (_) async {
      reads++;
      return wrong;
    });
    final facts = await readQaFullUiCapability();
    expect(allowed(native: facts), isFalse);
    expect(reads, 1);
  });

  test('runtime warmup is requested once only after the positive handshake',
      () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(qaChannel, (call) async {
      calls.add(call.method);
      if (call.method == 'qaUiCapability') return _native;
      if (call.method == 'qaWarmRuntime') return true;
      throw StateError('Unexpected native operation');
    });
    await requestQaFullUiRuntimeWarmup(profileAllowed: false);
    expect(calls, isEmpty);
    final facts = await readQaFullUiCapability();
    await requestQaFullUiRuntimeWarmup(profileAllowed: allowed(native: facts));
    expect(calls, ['qaUiCapability', 'qaWarmRuntime']);
  });

  test('unsupported or failed runtime warmup cannot fail UI bootstrap',
      () async {
    for (final error in <Object>[
      MissingPluginException(),
      PlatformException(code: 'qa_error'),
    ]) {
      messenger.setMockMethodCallHandler(qaChannel, (_) async => throw error);
      await expectLater(
          requestQaFullUiRuntimeWarmup(profileAllowed: true), completes);
    }
  });

  test('unanswered warmup is bounded and a late reply creates no new request',
      () async {
    var calls = 0;
    final reply = Completer<bool>();
    messenger.setMockMethodCallHandler(qaChannel, (_) {
      calls++;
      return reply.future;
    });
    await expectLater(
        requestQaFullUiRuntimeWarmup(
            profileAllowed: true, timeout: const Duration(milliseconds: 20)),
        completes);
    reply.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
  });
}
