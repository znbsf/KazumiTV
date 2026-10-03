enum PipEntryResult { entered, unsupported, failed, cancelled }

/// Platform effects are supplied by the page; this owns only the async request.
Future<PipEntryResult> requestPictureInPicture({
  required bool Function() isCurrent,
  required Future<bool> Function() isSupported,
  required Future<void> Function() waitForFrame,
  required Future<void> Function() updateActions,
  required Future<bool> Function() enter,
  required void Function(bool requested) onRequested,
}) async {
  if (!isCurrent()) return PipEntryResult.cancelled;
  final supported = await isSupported();
  if (!isCurrent()) return PipEntryResult.cancelled;
  if (!supported) return PipEntryResult.unsupported;
  onRequested(true);
  var entered = false;
  try {
    await waitForFrame();
    if (!isCurrent()) return PipEntryResult.cancelled;
    await updateActions();
    if (!isCurrent()) return PipEntryResult.cancelled;
    final result = await enter();
    if (!isCurrent()) return PipEntryResult.cancelled;
    entered = result;
    return entered ? PipEntryResult.entered : PipEntryResult.failed;
  } finally {
    if (!entered) onRequested(false);
  }
}
