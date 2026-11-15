import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/media_error_widget.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';

class VideoPlaybackFailure extends StatelessWidget {
  const VideoPlaybackFailure({
    super.key,
    required this.message,
    required this.isOffline,
    required this.onRetry,
    required this.onSelectEpisode,
    required this.onSelectSource,
    this.onDisableCache,
  });

  final String message;
  final bool isOffline;
  final VoidCallback onRetry;
  final VoidCallback onSelectEpisode;
  final VoidCallback onSelectSource;
  final VoidCallback? onDisableCache;

  @override
  Widget build(BuildContext context) => MediaErrorWidget(
        title: '暂时无法播放',
        errMsg: message,
        icon: Icons.videocam_off_outlined,
        onRetry: onRetry,
        retryText: '重试当前集',
        actions: [
          if (onDisableCache != null)
            StateActionButton.tonal(
              onPressed: onDisableCache,
              text: isOffline ? '关闭视频缓存并返回' : '关闭视频缓存并重试',
              icon: Icons.storage_outlined,
            ),
          StateActionButton.tonal(
            onPressed: onSelectEpisode,
            text: isOffline ? '选择集数' : '选集 / 换线路',
            icon: Icons.video_library_outlined,
          ),
          if (!isOffline)
            StateActionButton.tonal(
              onPressed: onSelectSource,
              text: '更换播放源',
              icon: Icons.swap_horiz_rounded,
            ),
        ],
      );
}
