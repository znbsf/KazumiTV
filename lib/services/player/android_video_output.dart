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
