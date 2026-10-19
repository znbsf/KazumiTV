import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tools/qa/source_batch/gecko_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(qaChannel, (call) async { calls.add(call); return null; });
  });
  tearDown(() => messenger.setMockMethodCallHandler(qaChannel, null));

  Future<void> event(int generation, String url) async {
    final done = Completer<void>();
    await messenger.handlePlatformMessage(qaChannel.name, codec.encodeMethodCall(
      MethodCall('geckoEvent', {'generation': generation, 'handler': 'VideoBridgeDebug', 'url': url})),
      (_) => done.complete());
    await done.future;
    await Future<void>.delayed(Duration.zero);
  }

  test('late Gecko page cannot resolve a new request or a retired session', () async {
    final controller = GeckoQaController('fixed-qa-ua');
    final urls = <String>[];
    final subscription = controller.onVideoURLParser.listen((value) => urls.add(value.url));
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
    await expectLater(controller.loadUrl('https://example.test/', true), throwsUnsupportedError);
    expect(calls.where((c) => c.method == 'geckoLoad'), isEmpty);
    await controller.dispose();
  });
}
