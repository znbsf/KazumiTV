import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/logging/playback_trace.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'normal mode persists failure after a new playback and restrictive log level',
      () async {
    final dir = await Directory.systemTemp.createTemp('kazumi-trace-');
    final previous = PathProviderPlatform.instance;
    final level = Logger.level;
    PathProviderPlatform.instance = _Paths(dir.path);
    Logger.level = Level.off;
    try {
      final failed = PlaybackTrace('native');
      failed.event('open', url: 'https://cdn.test/video?sign=DO_NOT_KEEP');
      failed.finish('native_error', error: 'TLS error -101');
      PlaybackTrace('native').finish('disposed');
      final file = await getLogsPath();
      String saved = '';
      // The existing logger serializes asynchronous disk appends.
      for (var i = 0; i < 100; i++) {
        saved = await file.readAsString();
        if (saved.contains('disposed')) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(saved, contains(failed.id));
      expect(saved, contains('TLS error -101'));
      expect(saved, contains('disposed'));
      expect(saved, isNot(contains('DO_NOT_KEEP')));
    } finally {
      Logger.level = level;
      PathProviderPlatform.instance = previous;
      await dir.delete(recursive: true);
    }
  });
}
