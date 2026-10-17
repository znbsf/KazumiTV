import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/services/player/audio_controller.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';
import '../tools/qa/playback_lifecycle.dart' as qa;

class _Downloads implements DownloadController {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected download call');
}

class _Audio implements AudioController {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected audio call');
}

class _Shaders implements ShaderAssetService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected shader call');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'real QA controller initializes once and synthetic metadata stays offline',
      () async {
    final player = qa.LifecycleQaPlayer(_Shaders(), _Downloads(), _Audio());
    final danmaku = player.danmaku;
    expect(identical(player.danmaku, danmaku), isTrue);
    final result = await player.danmaku.fetchDanmaku(0, 'Synthetic', 1);
    expect(result.hasDanmakus, isFalse);
    expect(result.isFailed, isFalse);
    expect(result.bangumiID, 0);
    final second = qa.LifecycleQaPlayer(_Shaders(), _Downloads(), _Audio());
    expect(identical(second.danmaku, danmaku), isFalse);
    expect((await second.danmaku.fetchDanmaku(0, 'Synthetic', 1)).isFailed,
        isFalse);
  });
}
