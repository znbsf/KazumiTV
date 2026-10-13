import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/tv_artwork_preparation.dart';
import 'package:kazumi/services/logging/logger.dart';

LinearGradient _vertical(Color color) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        color.withAlpha(0xCC),
        color.withAlpha(0x85),
        color.withAlpha(0x45),
        color.withAlpha(0xB8)
      ],
      stops: [0, .24, .62, 1],
    );
LinearGradient _horizontal(Color color) => LinearGradient(
      colors: [
        color.withAlpha(0x45),
        Colors.transparent,
        color.withAlpha(0x45)
      ],
      stops: [0, .55, 1],
    );

typedef TvBackdropRasterizer = Future<ui.Image> Function(TvArtworkGeometry);

/// The two original gradients composited over transparent pixels, at display
/// resolution. Their source-over result is independent of the cover below.
Future<ui.Image> rasterizeTvBackdropOverlay(TvArtworkGeometry geometry,
    {Color color = const Color(0xFF101611)}) async {
  if (!geometry.isUsable) throw ArgumentError('Invalid backdrop geometry');
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final rect = Rect.fromLTWH(
      0, 0, geometry.pixelWidth.toDouble(), geometry.pixelHeight.toDouble());
  canvas.drawRect(rect, Paint()..shader = _vertical(color).createShader(rect));
  canvas.drawRect(
      rect, Paint()..shader = _horizontal(color).createShader(rect));
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(geometry.pixelWidth, geometry.pixelHeight);
  } finally {
    picture.dispose();
  }
}

/// One geometry-specific texture; one async preparation plus latest geometry.
/// This separate cache is at most 16 MiB, in addition to the cover cache.
class TvBackdropOverlay extends StatefulWidget {
  const TvBackdropOverlay(
      {super.key,
      required this.geometry,
      this.rasterizer,
      this.color = const Color(0xFF101611)});
  final TvArtworkGeometry geometry;
  final Color color;
  @visibleForTesting
  final TvBackdropRasterizer? rasterizer;

  @override
  State<TvBackdropOverlay> createState() => _TvBackdropOverlayState();
}

class _TvBackdropOverlayState extends State<TvBackdropOverlay> {
  static const _maximumBytes = 16 * 1024 * 1024;
  late TvArtworkGeometry _requested = widget.geometry;
  TvArtworkGeometry? _resolved;
  ui.Image? _image;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(TvBackdropOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_requested != widget.geometry) {
      _requested = widget.geometry;
      _schedule();
    }
  }

  void _schedule() {
    if (_running || _requested == _resolved) return;
    _running = true;
    // Also keeps the oversize/failure fallback's state update outside build.
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_prepare()));
  }

  Future<void> _prepare() async {
    try {
      while (mounted && _requested != _resolved) {
        final geometry = _requested;
        ui.Image? prepared;
        if (geometry.isUsable && geometry.pixelBytes <= _maximumBytes) {
          try {
            prepared = widget.rasterizer != null
                ? await widget.rasterizer!(geometry)
                : await rasterizeTvBackdropOverlay(geometry,
                    color: widget.color);
          } catch (error) {
            KazumiLogger().w(
                'TV backdrop overlay preparation failed; retaining original gradients',
                error: error);
          }
        }
        if (!mounted) {
          prepared?.dispose();
          break;
        }
        if (geometry != _requested) {
          prepared?.dispose();
          continue;
        }
        final previous = _image;
        setState(() {
          _image = prepared;
          _resolved = geometry;
        });
        // Mounted pixel widgets keep their own handles until the next build.
        previous?.dispose();
      }
    } finally {
      _running = false;
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_image != null && _resolved == widget.geometry) {
      return _OverlayPixels(
          key: ValueKey(_resolved),
          image: _image!,
          scale: widget.geometry.devicePixelRatio);
    }
    return Stack(fit: StackFit.expand, children: [
      DecoratedBox(
          decoration: BoxDecoration(gradient: _vertical(widget.color))),
      DecoratedBox(
          decoration: BoxDecoration(gradient: _horizontal(widget.color))),
    ]);
  }
}

class _OverlayPixels extends StatefulWidget {
  const _OverlayPixels({super.key, required this.image, required this.scale});
  final ui.Image image;
  final double scale;
  @override
  State<_OverlayPixels> createState() => _OverlayPixelsState();
}

class _OverlayPixelsState extends State<_OverlayPixels> {
  late final ui.Image _image = widget.image.clone();
  @override
  void dispose() {
    _image.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RawImage(image: _image, scale: widget.scale, fit: BoxFit.fill);
}
