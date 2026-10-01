import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/platform/platform_environment_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.alexmercerind/media_kit_video');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('queries the frozen video plugin capability rather than guessing ABI',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'Utils.IsEmulator');
      return true;
    });
    expect(await PlatformEnvironmentService.isAndroidEmulator(), isTrue);
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    expect(await PlatformEnvironmentService.isAndroidEmulator(), isFalse);
  });

  test('missing or failed capability preserves existing physical TV behavior',
      () async {
    expect(await PlatformEnvironmentService.isAndroidEmulator(), isFalse);
    messenger.setMockMethodCallHandler(
        channel, (_) async => throw PlatformException(code: 'unavailable'));
    expect(await PlatformEnvironmentService.isAndroidEmulator(), isFalse);
  });
}
