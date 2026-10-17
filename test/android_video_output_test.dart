import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/android_video_output.dart';

void main() {
  group('shared production and health configuration', () {
    test('TV emulator auto disables acceleration and decoder together', () {
      final c = resolveAndroidVideoConfiguration(configuredOutput: 'auto',
        isTv: true, androidSdkVersion: 36, isEmulator: true,
        hardwareAcceleration: true, hardwareDecoder: 'auto-safe');
      expect(c.output, 'gpu'); expect(c.hardwareAcceleration, isFalse);
      expect(c.hardwareDecoder, 'no'); expect(c.effectiveHardwareDecoder, 'no');
    });
    test('real TV auto preserves established direct MediaCodec contract', () {
      final c = resolveAndroidVideoConfiguration(configuredOutput: 'auto',
        isTv: true, androidSdkVersion: 28, isEmulator: false,
        hardwareAcceleration: false, hardwareDecoder: 'no');
      expect(c.output, 'mediacodec_embed'); expect(c.hardwareAcceleration, isTrue);
      expect(c.effectiveHardwareDecoder, 'mediacodec');
    });
    test('explicit renderer on emulator keeps user decode choices', () {
      for (final renderer in ['gpu', 'gpu-next']) {
        for (final enabled in [true, false]) {
          final c = resolveAndroidVideoConfiguration(configuredOutput: renderer,
            isTv: true, androidSdkVersion: 36, isEmulator: true,
            hardwareAcceleration: enabled, hardwareDecoder: 'mediacodec-copy');
          expect(c.output, renderer); expect(c.hardwareAcceleration, enabled);
          expect(c.hardwareDecoder, 'mediacodec-copy');
          expect(c.effectiveHardwareDecoder, enabled ? 'mediacodec-copy' : 'no');
        }
      }
    });
    test('explicit direct output retains its required decoder on emulator', () {
      final c = resolveAndroidVideoConfiguration(configuredOutput: 'mediacodec_embed',
        isTv: true, androidSdkVersion: 36, isEmulator: true,
        hardwareAcceleration: false, hardwareDecoder: 'no');
      expect(c.output, 'mediacodec_embed'); expect(c.hardwareAcceleration, isTrue);
      expect(c.effectiveHardwareDecoder, 'mediacodec');
    });
    test('mobile auto remains SDK dependent and honors decode switch', () {
      for (final sdk in [33,34]) {
        final c = resolveAndroidVideoConfiguration(configuredOutput: 'auto',
          isTv: false, androidSdkVersion: sdk, isEmulator: true,
          hardwareAcceleration: false, hardwareDecoder: 'auto-safe');
        expect(c.output, sdk < 34 ? 'gpu' : 'gpu-next');
        expect(c.hardwareAcceleration, isFalse);
        expect(c.hardwareDecoder, 'auto-safe'); expect(c.effectiveHardwareDecoder, 'no');
      }
    });
  });

  test(
      'confirmed TV emulator auto disables embedded output and hardware decode',
      () {
    expect(
        selectAndroidVideoOutput(
            configuredOutput: 'auto',
            isTv: true,
            androidSdkVersion: 36,
            isEmulator: true),
        'gpu');
    expect(
        usesAndroidAutoSoftwareOutput(
            configuredOutput: 'auto', isTv: true, isEmulator: true),
        isTrue);
    expect(
        usesAndroidDirectMediaCodecOutput(
            configuredOutput: 'auto', isTv: true, isEmulator: true),
        isFalse);
    expect(
        usesAndroidAutoSoftwareOutput(
            configuredOutput: 'auto', isTv: true, isEmulator: false),
        isFalse);
  });

  test('explicit output and mobile auto remain user and platform choices', () {
    expect(
        selectAndroidVideoOutput(
            configuredOutput: 'mediacodec_embed',
            isTv: true,
            androidSdkVersion: 36,
            isEmulator: true),
        'mediacodec_embed');
    expect(
        usesAndroidAutoSoftwareOutput(
            configuredOutput: 'mediacodec_embed', isTv: true, isEmulator: true),
        isFalse);
    expect(
        selectAndroidVideoOutput(
            configuredOutput: 'auto',
            isTv: false,
            androidSdkVersion: 36,
            isEmulator: true),
        'gpu-next');
  });
  test('TV auto uses the direct MediaCodec Surface path', () {
    expect(
      selectAndroidVideoOutput(
        configuredOutput: 'auto',
        isTv: true,
        androidSdkVersion: 28,
      ),
      'mediacodec_embed',
    );
  });

  test('mobile auto keeps the SDK-dependent GPU outputs', () {
    expect(
      selectAndroidVideoOutput(
        configuredOutput: 'auto',
        isTv: false,
        androidSdkVersion: 33,
      ),
      'gpu',
    );
    expect(
      selectAndroidVideoOutput(
        configuredOutput: 'auto',
        isTv: false,
        androidSdkVersion: 34,
      ),
      'gpu-next',
    );
  });

  test('explicit renderer choice is never overridden', () {
    expect(
      selectAndroidVideoOutput(
        configuredOutput: 'gpu',
        isTv: true,
        androidSdkVersion: 28,
      ),
      'gpu',
    );
  });

  test('direct output capability follows TV auto and explicit selection', () {
    expect(
      usesAndroidDirectMediaCodecOutput(
        configuredOutput: 'auto',
        isTv: true,
      ),
      isTrue,
    );
    expect(
      usesAndroidDirectMediaCodecOutput(
        configuredOutput: 'auto',
        isTv: false,
      ),
      isFalse,
    );
    expect(
      usesAndroidDirectMediaCodecOutput(
        configuredOutput: 'mediacodec_embed',
        isTv: false,
      ),
      isTrue,
    );
  });
}
