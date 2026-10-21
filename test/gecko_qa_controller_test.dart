import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tools/qa/source_batch/gecko_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();
  final calls = <MethodCall>[];
  var nativeOwners = 0;
  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(qaChannel, (call) async {
      calls.add(call);
      if (call.method == 'geckoAcquire') return ++nativeOwners;
      return call.method == 'geckoClose' ? true : null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(qaChannel, null));

  Future<void> event(int generation, String url, {int? owner}) async {
    final done = Completer<void>();
    owner ??= (calls.lastWhere((c) => c.method == 'geckoLoad').arguments
        as Map)['owner'] as int;
    await messenger.handlePlatformMessage(
        qaChannel.name,
        codec.encodeMethodCall(MethodCall('geckoEvent', {
          'generation': generation,
          'owner': owner,
          'handler': 'VideoBridgeDebug',
          'url': url
        })),
        (_) => done.complete());
    await done.future;
    await Future<void>.delayed(Duration.zero);
  }

  test('late Gecko page cannot resolve a new request or a retired session',
      () async {
    final controller = GeckoQaController('fixed-qa-ua');
    final urls = <String>[];
    final subscription =
        controller.onVideoURLParser.listen((value) => urls.add(value.url));
    await controller.init();
    await controller.loadUrl('https://example.test/one', false);
    final first = (calls.last.arguments as Map)['generation'] as int;
    await controller.loadUrl('https://example.test/two', false);
    final second = (calls.last.arguments as Map)['generation'] as int;
    await event(first, 'https://example.test/stale.mp4');
    expect(urls, isEmpty);
    await event(second, 'https://example.test/current.mp4');
    expect(urls, ['https://example.test/current.mp4']);
    await controller.unloadPage();
    await event(second, 'https://example.test/retired.mp4');
    expect(urls.length, 1);
    await controller.dispose();
    await subscription.cancel();
  });

  test('prototype refuses unsupported iframe-only mode', () async {
    final controller = GeckoQaController('fixed-qa-ua');
    await controller.init();
    await expectLater(controller.loadUrl('https://example.test/', true),
        throwsUnsupportedError);
    expect(calls.where((c) => c.method == 'geckoLoad'), isEmpty);
    await controller.dispose();
  });

  test('old route retirement cannot clear or close a newer controller',
      () async {
    final release = Completer<bool>();
    var delayRelease = true;
    messenger.setMockMethodCallHandler(qaChannel, (call) async {
      calls.add(call);
      if (call.method == 'geckoAcquire') return ++nativeOwners;
      if (call.method == 'geckoClose') {
        if ((call.arguments as Map)['release'] == true && delayRelease) {
          return release.future;
        }
        return true;
      }
      return null;
    });
    final old = GeckoQaController('old');
    await old.init();
    await old.loadUrl('https://example.test/old', false);
    final oldArgs = Map.from(calls.last.arguments as Map);
    final retiring = old.dispose();
    final blocked = GeckoQaController('blocked');
    await expectLater(blocked.init(), throwsStateError);
    await blocked.dispose(); // never owned: must not clear old's handler
    delayRelease = false;
    release.complete(true);
    await retiring;
    final next = GeckoQaController('new');
    final urls = <String>[];
    final sub = next.onVideoURLParser.listen((e) => urls.add(e.url));
    await next.init();
    await next.loadUrl('https://example.test/new', false);
    final nextArgs = Map.from(calls.last.arguments as Map);
    expect(nextArgs['generation'], isNot(oldArgs['generation']));
    await old.dispose(); // idempotent old call must not detach next
    await event(oldArgs['generation'] as int, 'https://example.test/stale.mp4',
        owner: oldArgs['owner'] as int);
    await event(
        nextArgs['generation'] as int, 'https://example.test/wrong-owner.mp4',
        owner: oldArgs['owner'] as int);
    expect(urls, isEmpty);
    await event(nextArgs['generation'] as int, 'https://example.test/new.mp4');
    expect(urls, ['https://example.test/new.mp4']);
    await next.dispose();
    await sub.cancel();
  });

  test('late init after retirement cannot replace the next handler', () async {
    final init = Completer<void>();
    final initEntered = Completer<void>();
    var first = true;
    messenger.setMockMethodCallHandler(qaChannel, (call) async {
      calls.add(call);
      if (call.method == 'geckoAcquire') return ++nativeOwners;
      if (call.method == 'geckoInit' && first) {
        first = false;
        initEntered.complete();
        await init.future;
        return null;
      }
      return call.method == 'geckoClose' ? true : null;
    });
    final old = GeckoQaController('old');
    final rejected = expectLater(old.init(), throwsStateError);
    await initEntered.future;
    await old.dispose();
    final next = GeckoQaController('new');
    final urls = <String>[];
    final sub = next.onVideoURLParser.listen((e) => urls.add(e.url));
    await next.init();
    await next.loadUrl('https://example.test/new', false);
    init.complete();
    await rejected;
    await event((calls.last.arguments as Map)['generation'] as int,
        'https://example.test/new.mp4');
    expect(urls, hasLength(1));
    await next.dispose();
    await sub.cancel();
  });

  test('native busy rejection never closes another isolate owner', () async {
    messenger.setMockMethodCallHandler(qaChannel, (call) async {
      calls.add(call);
      if (call.method == 'geckoAcquire') {
        throw PlatformException(code: 'gecko_busy');
      }
      throw StateError('rejected acquisition must not send close');
    });
    final blocked = GeckoQaController('blocked');
    await expectLater(blocked.init(), throwsA(isA<PlatformException>()));
    await blocked.dispose();
    expect(calls.where((c) => c.method == 'geckoClose'), isEmpty);
    messenger.setMockMethodCallHandler(qaChannel, (call) async {
      calls.add(call);
      if (call.method == 'geckoAcquire') return ++nativeOwners;
      return call.method == 'geckoClose' ? true : null;
    });
    final next = GeckoQaController('next');
    await next.init();
    await next.dispose();
  });

  test('retirement waits for acquisition and closes only its returned token',
      () async {
    final acquired = Completer<int>();
    var first = true;
    messenger.setMockMethodCallHandler(qaChannel, (call) async {
      calls.add(call);
      if (call.method == 'geckoAcquire') {
        if (first) {
          first = false;
          return acquired.future;
        }
        return ++nativeOwners;
      }
      return call.method == 'geckoClose' ? true : null;
    });
    final old = GeckoQaController('old');
    final rejected = expectLater(old.init(), throwsStateError);
    final retirement = old.dispose();
    final blocked = GeckoQaController('blocked');
    await expectLater(blocked.init(), throwsStateError);
    await blocked.dispose();
    final token = ++nativeOwners;
    acquired.complete(token);
    await rejected;
    await retirement;
    expect(calls.where((c) => c.method == 'geckoInit'), isEmpty);
    expect((calls.last.arguments as Map)['owner'], token);
    final next = GeckoQaController('new');
    await next.init();
    await next.dispose();
  });

  // Last: an unconfirmed close deliberately keeps its process-local lease.
  test('unconfirmed native close quarantines the channel', () async {
    messenger.setMockMethodCallHandler(qaChannel, (call) async {
      calls.add(call);
      if (call.method == 'geckoAcquire') return ++nativeOwners;
      return call.method == 'geckoClose' ? false : null;
    });
    final old = GeckoQaController('old');
    await old.init();
    await expectLater(old.dispose(), throwsStateError);
    final next = GeckoQaController('new');
    await expectLater(next.init(), throwsStateError);
    await next.dispose();
  });
}
