import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/sync/webdav_remote_file_commit.dart';

void main() {
  for (final mode in ['throw', 'noop', 'corrupt', 'success']) {
    test('MOVE $mode never pre-deletes the destination', () async {
      final files = <String, String>{'/target': 'old'};
      final removed = <String>[];
      final operation = const WebDavRemoteFileCommitter().replaceFile(
        sourceFilePath: 'new',
        temporaryPath: '/cache',
        destinationPath: '/target',
        remove: (p) async {
          removed.add(p);
          files.remove(p);
        },
        uploadFromFile: (s, p) async {
          files[p] = s;
        },
        rename: (s, d) async {
          if (mode == 'throw') throw StateError('MOVE unsupported');
          if (mode == 'noop') return;
          files[d] = mode == 'corrupt' ? 'wrong' : files[s]!;
          files.remove(s);
        },
        exists: (p) async => files.containsKey(p),
        verify: (s, p) async => files[p] == s,
      );
      if (mode == 'success') {
        await operation;
        expect(files, {'/target': 'new'});
      } else {
        await expectLater(operation, throwsStateError);
        if (mode != 'corrupt') {
          expect(files['/target'], 'old');
          expect(files.values, contains('new'));
        }
      }
      expect(removed, mode == 'success' ? hasLength(1) : isEmpty);
      if (mode == 'corrupt') expect(files.values, contains('new'));
    });
  }
  test(
      'simultaneous uploads have separate staging and cannot delete each other',
      () async {
    final files = <String, String>{'/target': 'old'};
    final ready = Completer<void>();
    final staged = <String>[];
    Future<void> publish(String value) =>
        const WebDavRemoteFileCommitter().replaceFile(
          sourceFilePath: value,
          temporaryPath: '/cache',
          destinationPath: '/target',
          remove: (_) async => fail('must not delete'),
          uploadFromFile: (s, p) async {
            staged.add(p);
            files[p] = s;
            if (staged.length == 2 && !ready.isCompleted) ready.complete();
            await ready.future;
          },
          rename: (source, target) async =>
              throw StateError('MOVE unsupported'),
          exists: (p) async => files.containsKey(p),
          verify: (s, p) async => files[p] == s,
        );
    await Future.wait([
      expectLater(publish('one'), throwsStateError),
      expectLater(publish('two'), throwsStateError),
    ]);
    expect(staged.toSet(), hasLength(4));
    expect(files.values, containsAll(['old', 'one', 'two']));
  });
}
