import 'dart:async';

enum PlaybackFailureCategory {
  operationTimeout,
  network,
  parser,
  sourceOpen,
  releasedSession,
  unknown,
}

class PlayerErrorMapper {
  const PlayerErrorMapper._();

  /// Capture only a safe category while ownership is still valid. Handling can
  /// synchronously retire the player, so diagnostics must precede that callback.
  static void dispatchCurrentError(
    Object error, {
    required bool Function() isCurrent,
    required void Function(PlaybackFailureCategory) record,
    required void Function(PlaybackFailureCategory) handle,
  }) {
    if (!isCurrent()) return;
    final category = classify(error);
    record(category);
    handle(category);
  }

  static PlaybackFailureCategory classify(Object error) {
    if (error is TimeoutException)
      return PlaybackFailureCategory.operationTimeout;
    if (error is AssertionError &&
        error.message == '[Player] has been disposed') {
      return PlaybackFailureCategory.releasedSession;
    }
    final message = error.toString().trim();
    if (message == '[Player] has been disposed')
      return PlaybackFailureCategory.releasedSession;
    if ((message == 'Failed to recognize file format.' ||
        message == 'Failed to recognize file format'))
      return PlaybackFailureCategory.parser;
    // Do not infer network vs parser from the generic "Failed to open" error.
    if (message == 'Failed to open' || message == 'Failed to open file.') {
      return PlaybackFailureCategory.sourceOpen;
    }
    if (RegExp(
            r'^HTTP error (403 Forbidden|404 Not Found|500 Internal Server Error)$')
        .hasMatch(message)) {
      return PlaybackFailureCategory.network;
    }
    return PlaybackFailureCategory.unknown;
  }

  static String? toActionableMessage(
    Object error, {
    required bool isBuffering,
    bool softwareRecovery = false,
  }) {
    final category = classify(error);

    if (softwareRecovery) return '软件兼容播放失败，可重试当前集、更换视频源或退出播放';
    switch (category) {
      case PlaybackFailureCategory.operationTimeout:
        return '播放请求超时，可重试当前集或更换视频源';
      case PlaybackFailureCategory.network:
        return '视频请求失败，请检查网络、重试或更换视频源';
      case PlaybackFailureCategory.parser:
        return '无法识别视频格式，请重试或更换视频源';
      case PlaybackFailureCategory.sourceOpen:
        return '无法打开视频，原因尚未确定，请重试或更换视频源';
      case PlaybackFailureCategory.unknown:
        return '播放发生异常，原因尚未确定，可重试或更换视频源';
      case PlaybackFailureCategory.releasedSession:
        return '当前播放器会话已失效，请重试当前集或更换视频源';
    }
  }
}
