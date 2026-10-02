import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:kazumi/bean/widget/tv_artwork_preparation.dart';
import 'package:kazumi/bean/widget/tv_visuals.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/services/logging/logger.dart';

/// Presentation only. Dart repositories and playback retain their ownership.
class TvArtworkController extends ValueNotifier<BangumiItem?> {
  TvArtworkController() : super(null);
  (int?, String?)? _identity;
  String _imageUrl = '';
  String get imageUrl => _imageUrl;
  void select(BangumiItem? item, {String? imageUrl}) {
    final selectedUrl = imageUrl ?? item?.images['large'] ?? '';
    final identity = (item?.id, selectedUrl);
    if (_identity == identity) return;
    _identity = identity;
    _imageUrl = selectedUrl;
    // Home and detail keep the same Dart item. A medium -> large transition
    // must notify even though ValueNotifier's item equality has not changed.
    if (value == item) {
      notifyListeners();
    } else {
      value = item;
    }
  }
}

final tvArtworkController = TvArtworkController();

class TvAmbientBackdrop extends StatefulWidget {
  const TvAmbientBackdrop({super.key, this.oled = false});
  final bool oled;
  @override
  State<TvAmbientBackdrop> createState() => _TvAmbientBackdropState();
}

class _TvAmbientBackdropState extends State<TvAmbientBackdrop> {
  Timer? _dwell;
  int _revision = 0;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  TvPreparedArtwork? _displayed;
  TvArtworkGeometry? _geometry;
  final _preparer = TvArtworkPreparer(
    onError: (error, _) => KazumiLogger().w(
      'TV artwork preparation failed; retaining the original cover renderer',
      error: error,
    ),
  );

  @override
  void initState() {
    super.initState();
    tvArtworkController.addListener(_select);
    _select();
  }

  @override
  void didUpdateWidget(TvAmbientBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.oled != widget.oled) _select();
  }

  void _detach() {
    if (_stream != null && _listener != null)
      _stream!.removeListener(_listener!);
    _stream = null;
    _listener = null;
  }

  void _select() {
    final revision = ++_revision;
    _dwell?.cancel();
    _detach();
    _preparer.invalidate(clearCache: widget.oled);
    final url = tvArtworkController.imageUrl;
    if (widget.oled || url.isEmpty) {
      _show(null, revision);
      return;
    }
    // Same 260ms focus dwell and stale A -> B -> A isolation as native main.
    _dwell = Timer(const Duration(milliseconds: 260), () {
      if (!mounted || revision != _revision) return;
      final geometry = _geometry;
      if (geometry == null || !geometry.isUsable) return;
      final provider = ResizeImage.resizeIfNeeded(
        720,
        null,
        CachedNetworkImageProvider(url),
      );
      final stream = provider.resolve(ImageConfiguration.empty);
      _stream = stream;
      final listener = ImageStreamListener(
        (info, _) {
          try {
            if (!mounted || revision != _revision) return;
            _detach();
            // prepare clones the decoded image before its first await; this
            // stream handle can then be released even while rasterizing.
            unawaited(_prepare(info, url, geometry, revision));
          } finally {
            info.dispose();
          }
        },
        onError: (Object error, StackTrace? stack) {
          if (!mounted || revision != _revision) return;
          _detach();
          _show(null, revision);
        },
      );
      _listener = listener;
      stream.addListener(listener);
    });
  }

  Future<void> _prepare(ImageInfo info, String url, TvArtworkGeometry geometry,
      int revision) async {
    final frame = await _preparer.prepare(
      url: url,
      source: info,
      geometry: geometry,
    );
    if (frame != null) _show(frame, revision);
  }

  void _observeGeometry(TvArtworkGeometry geometry) {
    final next = geometry.isUsable ? geometry : null;
    if (_geometry == next) return;
    final previous = _geometry;
    _geometry = next;
    // First layout supplies bounds to the original focus-dwell timer. Later
    // layout/DPR changes invalidate work immediately, before any await returns.
    if (previous == null && _dwell?.isActive == true) return;
    final revision = ++_revision;
    _dwell?.cancel();
    _detach();
    _preparer.invalidate(clearCache: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && revision == _revision && _geometry == next) _select();
    });
  }

  void _show(TvPreparedArtwork? frame, int revision) {
    void apply() {
      if (!mounted || revision != _revision) {
        frame?.dispose();
        return;
      }
      if (_displayed?.key == frame?.key) {
        frame?.dispose();
        return;
      }
      final previous = _displayed;
      setState(() {
        _displayed = frame;
      });
      // Fade children own clones for their complete outgoing lifetime.
      previous?.dispose();
    }

    // A newly built route may choose its artwork while this sibling backdrop
    // already completed its build. Publish after the frame in that case.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  @override
  void dispose() {
    ++_revision;
    _dwell?.cancel();
    _detach();
    _preparer.dispose();
    _displayed?.dispose();
    tvArtworkController.removeListener(_select);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          _observeGeometry(TvArtworkGeometry(
            constraints.biggest,
            MediaQuery.devicePixelRatioOf(context),
          ));
          return IgnorePointer(
            child: ColoredBox(
              color: widget.oled ? Colors.black : TvVisuals.background,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (!widget.oled)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 600),
                      layoutBuilder: (current, previous) => Stack(
                        fit: StackFit.expand,
                        children: [...previous, if (current != null) current],
                      ),
                      child: _displayed == null
                          ? const SizedBox.expand()
                          : Opacity(
                              key: ValueKey(_displayed!.key),
                              opacity: _displayed!.key.landscape ? 1 : .84,
                              child: _TvArtworkPixels(artwork: _displayed!),
                            ),
                    ),
                  if (!widget.oled)
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xCC101611),
                            Color(0x85101611),
                            Color(0x45101611),
                            Color(0xB8101611),
                          ],
                          stops: [0, .24, .62, 1],
                        ),
                      ),
                    ),
                  if (!widget.oled)
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0x45101611),
                            Colors.transparent,
                            Color(0x45101611),
                          ],
                          stops: [0, .55, 1],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
}

class _TvArtworkPixels extends StatefulWidget {
  const _TvArtworkPixels({required this.artwork});
  final TvPreparedArtwork artwork;

  @override
  State<_TvArtworkPixels> createState() => _TvArtworkPixelsState();
}

class _TvArtworkPixelsState extends State<_TvArtworkPixels> {
  late final ui.Image _image = widget.artwork.image.clone();

  @override
  void dispose() {
    _image.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final artwork = widget.artwork;
    final pixels = RawImage(
      image: _image,
      scale: artwork.scale,
      fit: artwork.key.prefiltered ? BoxFit.fill : BoxFit.cover,
      filterQuality: FilterQuality.medium,
    );
    if (artwork.key.prefiltered || artwork.key.landscape) return pixels;
    // Bounded fallback for oversized geometry or failed preparation; never
    // change the requested visual style to conceal a rasterization failure.
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: pixels,
    );
  }
}
