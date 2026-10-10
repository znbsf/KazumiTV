import 'dart:collection';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/tv_visuals.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/utils/image_extension.dart';

class NetworkImgLayer extends StatelessWidget {
  const NetworkImgLayer({
    super.key,
    this.src,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.type,
    this.fadeOutDuration,
    this.fadeInDuration,
    this.origAspectRatio,
    this.filterQuality = FilterQuality.high,
    this.color,
    this.colorBlendMode,
    this.placeholderSrc,
  });

  final String? src;
  final double width;
  final double height;
  final BoxFit fit;
  final String? type;
  final Duration? fadeOutDuration;
  final Duration? fadeInDuration;
  final double? origAspectRatio;
  final FilterQuality filterQuality;
  final Color? color;
  final BlendMode? colorBlendMode;

  /// The same work's list cover, retained while a larger TV detail image loads.
  /// Exact URLs keep covers from different works or catalog mirrors separate.
  final String? placeholderSrc;

  @visibleForTesting
  static void clearTvCoverMemory() => _TvDisplayedCovers.clear();

  /// P1/mirror medium covers are only 200px wide: too small for ~324px TV
  /// home posters. Common is a bounded 400px source; compact rows retain the
  /// thumbnail. Decode sizing still follows the rendered size and device DPR.
  static String tvListCoverUrl(Map<String, String> images,
      {bool thumbnail = false}) {
    final kinds = thumbnail
        ? ['medium', 'common', 'large']
        : ['common', 'large', 'medium'];
    for (final kind in kinds) {
      final url = images[kind]?.trim() ?? '';
      if (url.isNotEmpty) return url;
    }
    return '';
  }

  static String tvDetailCoverUrl(Map<String, String> images) {
    final large = images['large']?.trim() ?? '';
    return large.isNotEmpty ? large : tvListCoverUrl(images);
  }

  /// Detail may be opened from either a thumbnail row or a larger home card.
  /// Reuse the exact frame the user saw, without assuming one list URL size.
  static String tvInitialCoverUrl(Map<String, String> images) =>
      _TvDisplayedCovers.latestUrl(images.values) ?? tvListCoverUrl(images);

  static Widget heroFlightShuttleBuilder(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final fromHero = fromHeroContext.widget as Hero;
    final toHero = toHeroContext.widget as Hero;
    final heroContext = flightDirection == HeroFlightDirection.push
        ? fromHeroContext
        : toHeroContext;
    final hero =
        flightDirection == HeroFlightDirection.push ? fromHero : toHero;

    return InheritedTheme.captureAll(
      heroContext,
      Material(
        type: MaterialType.transparency,
        child: hero.child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (TvMode.enabled) return _TvNetworkImage(layer: this);
    final imageUrl = src ?? '';
    if (imageUrl.isEmpty) {
      return _placeholder(context);
    }

    final (memCacheWidth, memCacheHeight) = _cacheSize(context);
    return ClipRRect(
      clipBehavior: Clip.antiAlias,
      borderRadius: _borderRadius,
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        fit: fit,
        fadeOutDuration: fadeOutDuration ?? const Duration(milliseconds: 120),
        fadeInDuration: fadeInDuration ?? const Duration(milliseconds: 120),
        filterQuality: filterQuality,
        color: color,
        colorBlendMode: colorBlendMode,
        errorListener: (e) {
          KazumiLogger().w("NetworkImage: network image load error", error: e);
        },
        errorWidget: (context, url, error) => _placeholder(context),
        placeholder: (context, url) => _placeholder(context),
      ),
    );
  }

  (int?, int?) _cacheSize(BuildContext context) {
    final cacheWidth = width.cacheSize(context);
    final cacheHeight = height.cacheSize(context);
    final aspectRatio = width / height;
    final sourceAspectRatio = origAspectRatio;

    switch (fit) {
      case BoxFit.none:
      case BoxFit.scaleDown:
        // These modes depend on the original image dimensions.
        return (null, null);
      case BoxFit.fill:
        return (cacheWidth, cacheHeight);
      case BoxFit.fitWidth:
        return (cacheWidth, null);
      case BoxFit.fitHeight:
        return (null, cacheHeight);
      case BoxFit.contain:
        // A single decode axis preserves unknown source proportions.
        return sourceAspectRatio != null && sourceAspectRatio > aspectRatio
            ? (cacheWidth, null)
            : (null, cacheHeight);
      case BoxFit.cover:
        // Decode enough pixels along the axis that fills the box.
        if (sourceAspectRatio != null) {
          if (sourceAspectRatio < aspectRatio) return (cacheWidth, null);
          if (sourceAspectRatio > aspectRatio) return (null, cacheHeight);
        } else {
          if (aspectRatio > 1) return (null, cacheHeight);
          if (aspectRatio < 1) return (cacheWidth, null);
        }
        return (cacheWidth, cacheHeight);
    }
  }

  BorderRadius get _borderRadius => BorderRadius.circular(switch (type) {
        'avatar' => 50,
        'emote' => 0,
        _ => StyleString.imgRadius.x,
      });

  Widget _placeholder(BuildContext context) {
    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .onInverseSurface
            .withValues(alpha: 0.4),
        borderRadius: _borderRadius,
      ),
      child: type == 'bg'
          ? const SizedBox()
          : Center(
              child: Image.asset(
                type == 'avatar'
                    ? 'assets/images/noface.jpeg'
                    : 'assets/images/loading.png',
                width: width,
                height: height,
                cacheWidth: width.cacheSize(context),
                cacheHeight: height.cacheSize(context),
              ),
            ),
    );
  }
}

/// Retain only frames that TV cards have actually displayed. The normal Flutter
/// image cache uses decode size in its key, so a larger detail request cannot
/// reliably use the list frame as its immediate placeholder.
abstract final class _TvDisplayedCovers {
  static final _frames = LinkedHashMap<String, ImageInfo>();
  static const _maximumCount = 24;
  static const _maximumBytes = 32 * 1024 * 1024;
  static int _bytes = 0;

  static int _size(ImageInfo info) => info.image.width * info.image.height * 4;

  static String? latestUrl(Iterable<String> candidates) {
    final urls = candidates.map((url) => url.trim()).toSet();
    for (final url in _frames.keys.toList().reversed) {
      if (urls.contains(url)) return url;
    }
    return null;
  }

  static ImageInfo? read(String url) {
    final frame = _frames.remove(url);
    if (frame == null) return null;
    _frames[url] = frame;
    return frame.clone();
  }

  static void remember(String url, ImageInfo info) {
    if (_size(info) > _maximumBytes) return;
    final old = _frames.remove(url);
    if (old != null) {
      _bytes -= _size(old);
      old.dispose();
    }
    _frames[url] = info.clone();
    _bytes += _size(info);
    while (_frames.length > _maximumCount || _bytes > _maximumBytes) {
      final removed = _frames.remove(_frames.keys.first)!;
      _bytes -= _size(removed);
      removed.dispose();
    }
  }

  static void clear() {
    for (final frame in _frames.values) {
      frame.dispose();
    }
    _frames.clear();
    _bytes = 0;
  }
}

class _TvNetworkImage extends StatefulWidget {
  const _TvNetworkImage({required this.layer});
  final NetworkImgLayer layer;

  @override
  State<_TvNetworkImage> createState() => _TvNetworkImageState();
}

class _TvNetworkImageState extends State<_TvNetworkImage> {
  ImageProvider? _provider;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _displayed;
  int _request = 0;
  int _frame = 0;
  bool _failed = false;

  NetworkImgLayer get layer => widget.layer;
  String get _url => (layer.src?.isNotEmpty ?? false)
      ? layer.src!
      : layer.placeholderSrc ?? '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_TvNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layer.src != layer.src) {
      // A new work must never inherit the previous work's poster. An explicit
      // unchanged list URL identifies a larger request for the same work.
      if (layer.placeholderSrc == null ||
          layer.placeholderSrc != oldWidget.layer.placeholderSrc) {
        _replace(null);
      }
    }
    _resolve();
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  void _replace(ImageInfo? frame) {
    final previous = _displayed;
    _displayed = frame;
    ++_frame;
    // The old RawImage may still be painted until the next frame. Each switcher
    // child also owns a clone for the entire outgoing transition.
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  void _resolve({bool retry = false}) {
    if (_url.isEmpty) {
      ++_request;
      _detach();
      _provider = null;
      _replace(null);
      return;
    }
    final (width, height) = layer._cacheSize(context);
    final next = ResizeImage.resizeIfNeeded(
      width,
      height,
      CachedNetworkImageProvider(_url),
    );
    if (!retry && _provider == next) return;
    final request = ++_request;
    _detach();
    _provider = next;
    _failed = false;
    if (_displayed == null) {
      final known = _TvDisplayedCovers.read(_url) ??
          _TvDisplayedCovers.read(layer.placeholderSrc ?? '');
      if (known != null) _replace(known);
    }
    final stream = next.resolve(createLocalImageConfiguration(context));
    _stream = stream;
    final listener = ImageStreamListener(
      (info, synchronous) {
        if (!mounted || request != _request) {
          info.dispose();
          return;
        }
        if (layer.type == null) _TvDisplayedCovers.remember(_url, info);
        setState(() {
          _failed = false;
          _replace(info);
        });
      },
      onError: (Object error, StackTrace? stack) {
        if (!mounted || request != _request) return;
        KazumiLogger().w(
          'NetworkImage: network image load error',
          error: error,
        );
        setState(() => _failed = true);
      },
    );
    _listener = listener;
    stream.addListener(listener);
  }

  @override
  void dispose() {
    ++_request;
    _detach();
    _displayed?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: layer.width,
      height: layer.height,
      child: ClipRRect(
        borderRadius: layer._borderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              // Keep the displayed opaque cover underneath the incoming fade.
              // Fading both layers out/in exposes the dark page at mid-handoff.
              switchOutCurve: const Threshold(0.0),
              duration: layer.placeholderSrc != null
                  ? const Duration(milliseconds: 180)
                  : layer.fadeInDuration ?? const Duration(milliseconds: 120),
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                children: [...previous, if (current != null) current],
              ),
              child: _displayed == null
                  ? layer._placeholder(context)
                  : _TvCoverFrame(
                      key: ValueKey(_frame),
                      frame: _displayed!,
                      layer: layer,
                    ),
            ),
            if (_failed && layer.placeholderSrc != null)
              Align(
                alignment: Alignment.bottomCenter,
                child: ColoredBox(
                  color: TvVisuals.background.withValues(alpha: .88),
                  child: TextButton.icon(
                    onPressed: () => setState(() => _resolve(retry: true)),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('重试封面', style: TvVisuals.control),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Own the outgoing frame independently of requests and the bounded cover cache.
class _TvCoverFrame extends StatefulWidget {
  const _TvCoverFrame({super.key, required this.frame, required this.layer});
  final ImageInfo frame;
  final NetworkImgLayer layer;

  @override
  State<_TvCoverFrame> createState() => _TvCoverFrameState();
}

class _TvCoverFrameState extends State<_TvCoverFrame> {
  late final ImageInfo _frame = widget.frame.clone();

  @override
  void dispose() {
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawImage(
        image: _frame.image,
        scale: _frame.scale,
        fit: widget.layer.fit,
        filterQuality: widget.layer.filterQuality,
        color: widget.layer.color,
        colorBlendMode: widget.layer.colorBlendMode,
      );
}
