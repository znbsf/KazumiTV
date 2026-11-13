import 'package:uuid/uuid.dart';

typedef WebDavRemoveRemoteFile = Future<void> Function(String path);
typedef WebDavUploadRemoteFile = Future<void> Function(
    String source, String path);
typedef WebDavRenameRemoteFile = Future<void> Function(
    String source, String target);
typedef WebDavRemoteEntryExists = Future<bool> Function(String path);
typedef WebDavVerifyRemoteFile = Future<bool> Function(
    String source, String path);

class WebDavRemoteFileCommitter {
  const WebDavRemoteFileCommitter();

  Future<void> replaceFile({
    required String sourceFilePath,
    required String temporaryPath,
    required String destinationPath,
    required WebDavRemoveRemoteFile remove,
    required WebDavUploadRemoteFile uploadFromFile,
    required WebDavRenameRemoteFile rename,
    required WebDavRemoteEntryExists exists,
    required WebDavVerifyRemoteFile verify,
    // Kept for source compatibility; deleting the destination is never safe.
    bool removeDestinationBeforeRename = false,
  }) async {
    final staged = '$temporaryPath.${const Uuid().v4()}';
    // No cleanup on failure: a server may have accepted bytes before throwing.
    // The unique staged file remains available for recovery and cannot collide
    // with another device's in-flight upload.
    await uploadFromFile(sourceFilePath, staged);
    if (!await verify(sourceFilePath, staged)) {
      throw StateError(
          'WebDAV upload verification failed; staged file retained');
    }
    // Keep a verified recovery copy until MOVE and readback both succeed.
    // Some broken servers consume the source while publishing wrong bytes.
    final moving = '$staged.move';
    await uploadFromFile(sourceFilePath, moving);
    if (!await verify(sourceFilePath, moving)) {
      throw StateError(
          'WebDAV upload verification failed; recovery copy retained');
    }
    await rename(moving, destinationPath);
    if (await exists(moving) ||
        !await exists(destinationPath) ||
        !await verify(sourceFilePath, destinationPath)) {
      throw StateError(
          'WebDAV MOVE verification failed; recovery copy retained');
    }
    // Cleanup failure is recoverable and does not invalidate the verified write.
    try {
      await remove(staged);
    } catch (_) {}
  }
}
