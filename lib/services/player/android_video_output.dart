/// Resolves the Android video output while preserving explicit user choices.
/// TV defaults to MediaCodec's embedded Surface path to avoid copying every
/// decoded frame through Flutter's SurfaceTexture/GPU composition pipeline.
String selectAndroidVideoOutput({
  required String configuredOutput,
  required bool isTv,
  required int androidSdkVersion,
  bool isEmulator = false,
}) {
  if (configuredOutput != 'auto') return configuredOutput;
  if (usesAndroidAutoSoftwareOutput(
    configuredOutput: configuredOutput,
    isTv: isTv,
    isEmulator: isEmulator,
  )) {
    return 'gpu';
  }
  if (isTv) return 'mediacodec_embed';
  return androidSdkVersion >= 34 ? 'gpu-next' : 'gpu';
}

bool usesAndroidDirectMediaCodecOutput({
  required String configuredOutput,
  required bool isTv,
  bool isEmulator = false,
}) {
  return configuredOutput == 'mediacodec_embed' ||
      (configuredOutput == 'auto' && isTv && !isEmulator);
}

bool usesAndroidAutoSoftwareOutput({
  required String configuredOutput,
  required bool isTv,
  required bool isEmulator,
}) =>
    configuredOutput == 'auto' && isTv && isEmulator;

/// Complete Android video/decode selection shared by playback and health probes.
/// Renderer-only selection is insufficient: emulator auto also disables hwdec.
class AndroidVideoConfiguration {
  const AndroidVideoConfiguration({
    required this.output,
    required this.hardwareAcceleration,
    required this.hardwareDecoder,
  });
  final String output;
  final bool hardwareAcceleration;
  final String hardwareDecoder;
  String get effectiveHardwareDecoder => hardwareAcceleration ? hardwareDecoder : 'no';
}

AndroidVideoConfiguration resolveAndroidVideoConfiguration({
  required String configuredOutput,
  required bool isTv,
  required int androidSdkVersion,
  required bool isEmulator,
  required bool hardwareAcceleration,
  required String hardwareDecoder,
}) {
  final output = selectAndroidVideoOutput(
    configuredOutput: configuredOutput,
    isTv: isTv,
    androidSdkVersion: androidSdkVersion,
    isEmulator: isEmulator,
  );
  if (usesAndroidAutoSoftwareOutput(
    configuredOutput: configuredOutput, isTv: isTv, isEmulator: isEmulator,
  )) {
    return AndroidVideoConfiguration(output: output,
      hardwareAcceleration: false, hardwareDecoder: 'no');
  }
  if (output == 'mediacodec_embed') {
    return AndroidVideoConfiguration(output: output,
      hardwareAcceleration: true, hardwareDecoder: 'mediacodec');
  }
  return AndroidVideoConfiguration(output: output,
    hardwareAcceleration: hardwareAcceleration, hardwareDecoder: hardwareDecoder);
}
