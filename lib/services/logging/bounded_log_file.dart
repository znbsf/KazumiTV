import 'dart:convert';
import 'dart:io';

/// Call under the logger's shared lock so rotation, reads and clear agree.
class BoundedLogFile {
  const BoundedLogFile(this.file, {this.maxBytes = 2 * 1024 * 1024});
  final File file;
  final int maxBytes;

  Future<void> append(String text) async {
    final bytes = utf8.encode(text);
    // Individual events are bounded before queueing by KazumiLogOutput.
    if (bytes.length > maxBytes) throw ArgumentError('Log event too large');
    final length = await file.exists() ? await file.length() : 0;
    if (length + bytes.length > maxBytes) {
      final oldest = File('${file.path}.2');
      if (await oldest.exists()) await oldest.delete();
      final previous = File('${file.path}.1');
      if (await previous.exists()) await previous.rename(oldest.path);
      if (await file.exists()) await file.rename(previous.path);
    }
    await file.writeAsBytes(bytes, mode: FileMode.append);
  }

  Future<String> tail({int maxBytes = 256 * 1024}) async {
    final chunks = <List<int>>[];
    var remaining = maxBytes;
    var truncated = false;
    for (final candidate in [
      file,
      File('${file.path}.1'),
      File('${file.path}.2')
    ]) {
      if (!await candidate.exists()) continue;
      final handle = await candidate.open();
      try {
        final length = await handle.length();
        final count = length.clamp(0, remaining);
        if (count < length) truncated = true;
        if (count > 0) {
          await handle.setPosition(length - count);
          chunks.insert(0, await handle.read(count));
          remaining -= count;
        }
      } finally {
        await handle.close();
      }
    }
    var text =
        utf8.decode(chunks.expand((c) => c).toList(), allowMalformed: true);
    if (truncated) {
      final newline = text.indexOf('\n');
      text = newline < 0 ? '' : text.substring(newline + 1);
      text = '（仅显示最近日志，较早内容已省略）\n$text';
    }
    return text;
  }

  Future<void> clear() async {
    await file.writeAsString('');
    for (final suffix in ['.1', '.2']) {
      final archive = File('${file.path}$suffix');
      if (await archive.exists()) await archive.delete();
    }
  }
}
