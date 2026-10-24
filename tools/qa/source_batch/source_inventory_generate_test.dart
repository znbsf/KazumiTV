import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'source_inventory.dart';

/// Explicit offline entry point, not an automatic test of live websites.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('generate pinned catalog inventory without site requests', () async {
    const directory = String.fromEnvironment('SOURCE_INVENTORY_ROOT');
    if (directory.isEmpty) {
      throw StateError(
          'Pass --dart-define=SOURCE_INVENTORY_ROOT=<private snapshot>');
    }
    final root = Directory(directory);
    final inventory = await SourceInventory.generate(root);
    const sources = [
      'tools/qa/source_batch/source_inventory.dart',
      'tools/qa/source_batch/source_inventory.py',
      'tools/qa/source_batch/source_inventory_generate_test.dart',
    ];
    final revision = await Process.run('git', ['rev-parse', 'HEAD']);
    final status =
        await Process.run('git', ['status', '--porcelain', '--', ...sources]);
    inventory['generator'] = {
      'repository_commit':
          revision.exitCode == 0 ? revision.stdout.toString().trim() : null,
      'source_files_dirty': status.exitCode == 0
          ? status.stdout.toString().trim().isNotEmpty
          : null,
      'source_sha256': {
        for (final source in sources)
          source: sha256.convert(await File(source).readAsBytes()).toString()
      },
    };
    await SourceInventory.write(root, inventory);
    // Counts only; raw rule URLs/configuration stay in the private snapshot.
    // ignore: avoid_print
    print(inventory['counts']);
  });
}
