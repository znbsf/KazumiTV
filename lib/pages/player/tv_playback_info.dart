import 'package:kazumi/services/platform/app_remote.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/player/tv_player_controls.dart';
import 'package:kazumi/services/player/episode_identity.dart';

/// Only metadata already owned by playback. No catalogue or schedule requests.
class TvPlaybackInfoData {
  const TvPlaybackInfoData(
      {required this.title,
      required this.episode,
      required this.sourceName,
      required this.coverUrl,
      this.nextEpisode});
  final String title, episode, sourceName, coverUrl;
  final String? nextEpisode;

  factory TvPlaybackInfoData.fromPlayback(
      {required String title,
      required String fallbackTitle,
      required String sourceName,
      required Map<String, String> images,
      required List<Road> roads,
      required int roadIndex,
      required int episodeIndex}) {
    String episode = '集数暂不可用';
    String? nextEpisode;
    if (roadIndex >= 0 && roadIndex < roads.length) {
      final road = roads[roadIndex];
      final index = episodeIndex - 1;
      final count = road.data.length < road.identifier.length
          ? road.data.length
          : road.identifier.length;
      if (index >= 0 && index < count) {
        final label = road.identifier[index].trim();
        if (label.isNotEmpty) episode = label;
        final ordinal = ordinaryEpisodeOrdinal(label);
        if (ordinal != null &&
            road.identifier
                    .take(count)
                    .where((value) => ordinaryEpisodeOrdinal(value) == ordinal)
                    .length ==
                1 &&
            index + 1 < count &&
            road.data[index + 1].trim().isNotEmpty) {
          final next = road.identifier[index + 1].trim();
          if (ordinaryEpisodeOrdinal(next) == ordinal + 1 &&
              road.identifier
                      .take(count)
                      .where((label) =>
                          ordinaryEpisodeOrdinal(label) == ordinal + 1)
                      .length ==
                  1) {
            nextEpisode = next;
          }
        }
      }
    }
    final name = title.trim().isNotEmpty ? title.trim() : fallbackTitle.trim();
    final cover = NetworkImgLayer.tvInitialCoverUrl(images);
    final uri = Uri.tryParse(cover);
    return TvPlaybackInfoData(
        title: name.isEmpty ? '番剧资料暂不可用' : name,
        episode: episode,
        sourceName: sourceName.trim(),
        coverUrl: uri != null &&
                uri.host.isNotEmpty &&
                (uri.scheme == 'https' || uri.scheme == 'http')
            ? cover
            : '',
        nextEpisode: nextEpisode);
  }
}

/// Owns only its modal route; never pauses, resumes, seeks or changes episodes.
class TvPlaybackInfoPresenter {
  DialogRoute<void>? _route;
  bool _closing = false;
  bool get isOpen => _route != null;

  Future<void> show(BuildContext context,
      {required FocusNode fallbackFocus,
      required WidgetBuilder builder}) async {
    if (isOpen ||
        !context.mounted ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final previous = FocusManager.instance.primaryFocus;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
        context: context,
        builder: builder,
        themes: InheritedTheme.capture(from: context, to: navigator.context),
        barrierColor: Colors.transparent,
        barrierDismissible: true,
        settings: const RouteSettings(name: 'playback-info'));
    _route = route;
    final remoteLease = AppRemote.instance.register(
        label: '播放信息',
        priority: 20,
        commands: () => TvMode.enabled && route.isCurrent && !_closing
            ? {
                for (final key in ['info', 'blue'])
                  key: AppRemoteCommand(
                      label: '关闭播放信息',
                      invoke: () {
                        if (!route.isCurrent || _closing) return false;
                        close();
                        return true;
                      })
              }
            : {});
    try {
      await navigator.push(route);
    } finally {
      remoteLease.release();
      if (identical(_route, route)) {
        _route = null;
        _closing = false;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted || ModalRoute.of(context)?.isCurrent != true) {
          return;
        }
        final target = previous?.context != null && previous!.canRequestFocus
            ? previous
            : fallbackFocus;
        if (target.context != null && target.canRequestFocus) {
          target.requestFocus();
        }
      });
    }
  }

  void close() {
    final route = _route;
    if (route == null || _closing) return;
    _closing = true;
    _dismissRoute(route);
  }

  void _dismissRoute(DialogRoute<void> route) {
    if (!route.isActive) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _dismissRoute(route));
      return;
    }
    final navigator = route.navigator;
    if (navigator == null || !navigator.mounted) return;
    if (route.isCurrent) {
      navigator.pop();
    } else if (route.isActive) {
      navigator.removeRoute(route);
    }
  }
}

class TvPlaybackInfoCard extends StatelessWidget {
  const TvPlaybackInfoCard(
      {super.key, required this.info, required this.onClose});
  final TvPlaybackInfoData info;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget text(String value, {double size = 14, FontWeight? weight}) => Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: size, fontWeight: weight, color: colors.onSurface));
    return Focus(
        skipTraversal: true,
        onKeyEvent: (_, event) {
          final key = event.logicalKey;
          if (event is KeyDownEvent &&
              (key == LogicalKeyboardKey.escape ||
                  key == LogicalKeyboardKey.browserBack ||
                  key == LogicalKeyboardKey.goBack ||
                  key == LogicalKeyboardKey.info ||
                  key == LogicalKeyboardKey.colorF3Blue)) {
            onClose();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: 640,
                    maxHeight:
                        (MediaQuery.sizeOf(context).height - 32).clamp(1, 360)),
                child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: ColoredBox(
                      key: const ValueKey('playback-info-surface'),
                      color: colors.surface.withValues(alpha: .64),
                      child: Padding(
                          padding: const EdgeInsets.all(14),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            Flexible(
                                child: SingleChildScrollView(
                                    child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                  if (info.coverUrl.isNotEmpty) ...[
                                    Semantics(
                                        label: '番剧海报',
                                        image: true,
                                        child: ExcludeSemantics(
                                            child: NetworkImgLayer(
                                                src: info.coverUrl,
                                                width: 64,
                                                height: 86,
                                                fit: BoxFit.contain))),
                                    const SizedBox(width: 12),
                                  ],
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        text(info.title,
                                            size: 18, weight: FontWeight.w700),
                                        const SizedBox(height: 4),
                                        text(info.episode),
                                        if (info.sourceName.isNotEmpty)
                                          text('来源：${info.sourceName}',
                                              size: 12),
                                        if (info.nextEpisode != null)
                                          text('下一集：${info.nextEpisode}',
                                              size: 12),
                                      ])),
                                ]))),
                            const SizedBox(height: 8),
                            Align(
                                alignment: Alignment.centerRight,
                                child: TvPlayerAction(
                                    label: '返回播放',
                                    autofocus: true,
                                    onPressed: onClose)),
                          ])),
                    )),
              )),
        ));
  }
}
