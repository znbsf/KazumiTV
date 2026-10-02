import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

@immutable
class TvArtworkGeometry {
  const TvArtworkGeometry(this.logicalSize, this.devicePixelRatio);

  final Size logicalSize;
  final double devicePixelRatio;

  bool get isUsable =>
      logicalSize.isFinite &&
      !logicalSize.isEmpty &&
      devicePixelRatio.isFinite &&
      devicePixelRatio > 0;
  int get pixelWidth => (logicalSize.width * devicePixelRatio).ceil();
  int get pixelHeight => (logicalSize.height * devicePixelRatio).ceil();
  int get pixelBytes => pixelWidth * pixelHeight * 4;

  @override
  bool operator ==(Object other) =>
      other is TvArtworkGeometry &&
      other.logicalSize == logicalSize &&
      other.devicePixelRatio == devicePixelRatio;

  @override
  int get hashCode => Object.hash(logicalSize, devicePixelRatio);
}

@immutable
class TvArtworkKey {
  const TvArtworkKey(this.url, this.geometry,
      {required this.landscape, required this.prefiltered});

  final String url;
  final TvArtworkGeometry geometry;
  final bool landscape;
  final bool prefiltered;

  @override
  bool operator ==(Object other) =>
      other is TvArtworkKey &&
      other.url == url &&
      other.geometry == geometry &&
      other.landscape == landscape &&
      other.prefiltered == prefiltered;

  @override
  int get hashCode => Object.hash(url, geometry, landscape, prefiltered);
}

/// Each owner keeps its own image handle, including outgoing fade children.
class TvPreparedArtwork {
  TvPreparedArtwork(this.key, this.image, this.scale);

  final TvArtworkKey key;
  final ui.Image image;
  final double scale;

  TvPreparedArtwork clone() => TvPreparedArtwork(key, image.clone(), scale);
  void dispose() => image.dispose();
}

typedef TvArtworkRasterizer = Future<ui.Image> Function(
    ui.Image image, double scale, TvArtworkGeometry geometry);

/// Rasterize the same centered cover and logical sigma16 at the display DPR.
/// Opacity and gradients remain outside this picture, preserving fade blending.
Future<ui.Image> rasterizeTvPortraitArtwork(
    ui.Image image, double scale, TvArtworkGeometry geometry) async {
  if (!geometry.isUsable) throw ArgumentError('Invalid artwork geometry');
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final rect = Rect.fromLTWH(
      0, 0, geometry.pixelWidth.toDouble(), geometry.pixelHeight.toDouble());
  canvas.saveLayer(
    rect,
    Paint()
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: 16 * geometry.devicePixelRatio,
        sigmaY: 16 * geometry.devicePixelRatio,
      ),
  );
  paintImage(
    canvas: canvas,
    rect: rect,
    image: image,
    scale: scale,
    fit: BoxFit.cover,
    filterQuality: FilterQuality.medium,
  );
  canvas.restore();
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(geometry.pixelWidth, geometry.pixelHeight);
  } finally {
    picture.dispose();
  }
}

/// One raster operation plus the latest waiting selection. The cache does not
/// include handles held by active/outgoing fades or by the in-flight rasterizer.
class TvArtworkPreparer {
  TvArtworkPreparer({
    TvArtworkRasterizer? rasterizer,
    this.onError,
  }) : _rasterizer = rasterizer ?? rasterizeTvPortraitArtwork;

  static const maximumCacheEntries = 2;
  static const maximumCacheBytes = 16 * 1024 * 1024;
  final TvArtworkRasterizer _rasterizer;
  final void Function(Object, StackTrace)? onError;
  final _cache = LinkedHashMap<TvArtworkKey, TvPreparedArtwork>();
  int _cacheBytes = 0;
  int _generation = 0;
  bool _disposed = false;
  _Preparation? _active;
  _Preparation? _pending;

  @visibleForTesting
  int get cacheBytes => _cacheBytes;
  @visibleForTesting
  int get cacheEntries => _cache.length;
  @visibleForTesting
  bool get hasActivePreparation => _active != null;
  @visibleForTesting
  bool get hasPendingPreparation => _pending != null;

  void invalidate({bool clearCache = false}) {
    ++_generation;
    final pending = _pending;
    _pending = null;
    pending?.discard();
    if (clearCache) {
      for (final frame in _cache.values) {
        frame.dispose();
      }
      _cache.clear();
      _cacheBytes = 0;
    }
  }

  Future<TvPreparedArtwork?> prepare({
    required String url,
    required ImageInfo source,
    required TvArtworkGeometry geometry,
  }) {
    invalidate();
    if (_disposed || !geometry.isUsable) return Future.value(null);
    final landscape = source.image.width / source.image.height >= 1.35;
    // Large displays and raster failures retain the original renderer, rather
    // than silently downsampling or allocating an unbounded prepared texture.
    final prefilter = !landscape && geometry.pixelBytes <= maximumCacheBytes;
    final key = TvArtworkKey(url, geometry,
        landscape: landscape, prefiltered: prefilter);
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return Future.value(cached.clone());
    }
    if (!prefilter) {
      return Future.value(
          TvPreparedArtwork(key, source.image.clone(), source.scale));
    }
    final request =
        _Preparation(key, source.image.clone(), source.scale, _generation);
    if (_active == null) {
      unawaited(_run(request));
    } else {
      _pending = request;
    }
    return request.result.future;
  }

  bool _owns(_Preparation request) =>
      !_disposed && request.generation == _generation;

  void _remember(TvPreparedArtwork frame) {
    final old = _cache.remove(frame.key);
    if (old != null) {
      _cacheBytes -= old.image.width * old.image.height * 4;
      old.dispose();
    }
    _cache[frame.key] = frame.clone();
    _cacheBytes += frame.image.width * frame.image.height * 4;
    while (_cache.length > maximumCacheEntries ||
        _cacheBytes > maximumCacheBytes) {
      final removed = _cache.remove(_cache.keys.first)!;
      _cacheBytes -= removed.image.width * removed.image.height * 4;
      removed.dispose();
    }
  }

  Future<void> _run(_Preparation request) async {
    _active = request;
    ui.Image? rasterized;
    try {
      rasterized =
          await _rasterizer(request.image, request.scale, request.key.geometry);
      if (_owns(request)) {
        final frame = TvPreparedArtwork(
            request.key, rasterized, request.key.geometry.devicePixelRatio);
        rasterized = null;
        _remember(frame);
        request.result.complete(frame);
      } else {
        request.result.complete(null);
      }
    } catch (error, stack) {
      if (_owns(request)) {
        onError?.call(error, stack);
        request.result.complete(TvPreparedArtwork(
          TvArtworkKey(request.key.url, request.key.geometry,
              landscape: false, prefiltered: false),
          request.image.clone(),
          request.scale,
        ));
      } else {
        request.result.complete(null);
      }
    } finally {
      rasterized?.dispose();
      request.image.dispose();
      _active = null;
      final pending = _pending;
      _pending = null;
      if (pending != null) {
        if (_owns(pending)) {
          unawaited(_run(pending));
        } else {
          pending.discard();
        }
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    invalidate(clearCache: true);
  }
}

class _Preparation {
  _Preparation(this.key, this.image, this.scale, this.generation);

  final TvArtworkKey key;
  final ui.Image image;
  final double scale;
  final int generation;
  final result = Completer<TvPreparedArtwork?>();

  void discard() {
    image.dispose();
    result.complete(null);
  }
}
