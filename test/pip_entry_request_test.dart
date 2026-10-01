import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/pip_entry_request.dart';

void main() {
  for (final boundary in ['frame', 'actions']) {
    test('losing ownership while waiting for $boundary cancels and clears UI',
        () async {
      var current = true;
      var enterCalls = 0;
      final gate = Completer<void>();
      final started = Completer<void>();
      final requested = <bool>[];
      Future<void> wait() async {
        started.complete();
        await gate.future;
      }

      final pending = requestPictureInPicture(
          isCurrent: () => current,
          isSupported: () async => true,
          waitForFrame: boundary == 'frame' ? wait : () async {},
          updateActions: boundary == 'actions' ? wait : () async {},
          enter: () async {
            enterCalls++;
            return true;
          },
          onRequested: requested.add);
      await started.future;
      current = false;
      gate.complete();
      expect(await pending, PipEntryResult.cancelled);
      expect(enterCalls, 0);
      expect(requested, [true, false]);
    });
  }
  test('successful entry leaves the control flag for the native mode event',
      () async {
    final requested = <bool>[];
    final result = await requestPictureInPicture(
        isCurrent: () => true,
        isSupported: () async => true,
        waitForFrame: () async {},
        updateActions: () async {},
        enter: () async => true,
        onRequested: requested.add);
    expect(result, PipEntryResult.entered);
    expect(requested, [true]);
  });
  for (final outcome in ['failed', 'late', 'error']) {
    test('$outcome platform entry clears the local pending flag', () async {
      var current = true;
      final requested = <bool>[];
      final pending = requestPictureInPicture(
          isCurrent: () => current,
          isSupported: () async => true,
          waitForFrame: () async {},
          updateActions: () async {},
          enter: () async {
            if (outcome == 'error') throw StateError('platform failed');
            if (outcome == 'late') current = false;
            return outcome == 'late';
          },
          onRequested: requested.add);
      if (outcome == 'error') {
        await expectLater(pending, throwsStateError);
      } else {
        expect(
            await pending,
            outcome == 'failed'
                ? PipEntryResult.failed
                : PipEntryResult.cancelled);
      }
      expect(requested, [true, false]);
    });
  }
}
