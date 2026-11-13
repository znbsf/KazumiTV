import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/services/storage/open_box_preserving_data.dart';

void main() {
  test(
      'corrupt tail is retained byte for byte; explicit original restore reopens',
      () async {
    final dir = await Directory.systemTemp.createTemp('kazumi-storage-safety-');
    try {
      Hive.init(dir.path);
      final box = await openBoxPreservingData<String>('library');
      await box.put('saved', 'keep me');
      await box.close();
      final file = File('${dir.path}/library.hive');
      final original = await file.readAsBytes();
      await file.writeAsBytes([...original, 1, 2, 3]);
      final damaged = await file.readAsBytes();
      await expectLater(
          openBoxPreservingData<String>('library'), throwsA(isA<HiveError>()));
      expect(await file.readAsBytes(), damaged);
      await file.writeAsBytes(original);
      final recovered = await openBoxPreservingData<String>('library');
      expect(recovered.get('saved'), 'keep me');
      await recovered.close();
    } finally {
      await Hive.close();
      await dir.delete(recursive: true);
    }
  });
  for (final code in [5, 32, 33]) {
    test('OS error $code propagates without a second destructive attempt',
        () async {
      final failure = FileSystemException(
          'denied or locked', 'library', OSError('test', code));
      final hive = _FailingHive(failure);
      await expectLater(openBoxPreservingData<String>('library', hive: hive),
          throwsA(same(failure)));
      expect(hive.calls, 1);
    });
  }
}

class _FailingHive implements HiveInterface {
  _FailingHive(this.failure);
  final Object failure;
  int calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    expect(invocation.memberName, #openBox);
    expect(invocation.namedArguments[#crashRecovery], false);
    calls++;
    return Future<Box<String>>.error(failure);
  }
}
