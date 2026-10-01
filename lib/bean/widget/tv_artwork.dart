import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:kazumi/bean/widget/tv_visuals.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';

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
  ImageProvider? _displayed;
  bool _landscape = false;

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
    final url = tvArtworkController.imageUrl;
    if (widget.oled || url.isEmpty) {
      _show(null, revision);
      return;
    }
    // Same 260ms focus dwell and stale A -> B -> A isolation as native main.
    _dwell = Timer(const Duration(milliseconds: 260), () {
      if (!mounted || revision != _revision) return;
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
            _show(provider, revision,
                landscape: info.image.width / info.image.height >= 1.35);
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

  void _show(ImageProvider? provider, int revision, {bool landscape = false}) {
    void apply() {
      if (!mounted || revision != _revision) return;
      if (_displayed == provider && _landscape == landscape) return;
      setState(() {
        _displayed = provider;
        _landscape = landscape;
      });
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
    tvArtworkController.removeListener(_select);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
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
                          key: ValueKey(_displayed),
                          opacity: _landscape ? 1 : .84,
                          child: _landscape
                              ? Image(
                                  image: _displayed!,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                )
                              : ImageFiltered(
                                  imageFilter: ui.ImageFilter.blur(
                                    sigmaX: 16,
                                    sigmaY: 16,
                                  ),
                                  child: Image(
                                    image: _displayed!,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                  ),
                                ),
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
}
