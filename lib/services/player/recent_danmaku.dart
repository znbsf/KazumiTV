import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'package:kazumi/utils/danmaku.dart';

/// Video is local-first; comments are network-first. Empty responses and errors
/// may fall back, but cancellation must never revive a retired episode's load.
Future<(DanmakuLoadResult, bool)> loadRecentDanmaku({
  required Future<DanmakuLoadResult> Function() fresh,
  required Future<DanmakuLoadResult?> Function() cached,
  required Future<void> Function(DanmakuLoadResult) save,
  required bool Function() isCurrent,
  required bool deduplicate,
}) async {
  void check() {
    if (!isCurrent()) throw const DanmakuLoadCancelled();
  }

  DanmakuLoadResult result;
  try {
    result = await fresh();
  } on DanmakuLoadCancelled {
    rethrow;
  } catch (error) {
    result = DanmakuLoadResult.failed(bangumiID: 0, error: error);
  }
  check();
  if (result.hasDanmakus && result.danmakus.isNotEmpty) {
    try {
      await save(result);
    } catch (_) {}
    check();
    return (result, false);
  }
  DanmakuLoadResult? fallback;
  try {
    fallback = await cached();
  } catch (_) {}
  check();
  if (fallback == null || !fallback.hasDanmakus || fallback.danmakus.isEmpty) {
    return (result, false);
  }
  final prepared =
      await prepareDanmakus(fallback.danmakus, deduplicate: deduplicate);
  check();
  return (
    DanmakuLoadResult(
        danmakus: fallback.danmakus,
        bangumiID: fallback.bangumiID,
        status: DanmakuLoadStatus.success,
        prepared: prepared),
    true
  );
}
