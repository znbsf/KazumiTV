class PlayerErrorMapper {
  const PlayerErrorMapper._();

  static String? toActionableMessage(
    Object error, {
    required bool isBuffering,
    bool softwareRecovery = false,
  }) {
    final message = error.toString();
    if (message.contains('Failed to recognize file format') ||
        (isBuffering && message.contains('Failed to open'))) {
      return '加载失败, 请尝试更换其他视频来源';
    }
    return softwareRecovery
        ? '软件兼容播放失败，请重试当前集、更换播放源或退出播放'
        : null;
  }
}
