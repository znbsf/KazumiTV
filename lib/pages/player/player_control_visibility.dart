import 'package:flutter/material.dart';

/// Keeps the exit animation intact, then detaches reactive control contents.
class PlayerControlVisibility extends StatefulWidget {
  const PlayerControlVisibility({
    super.key,
    required this.visible,
    required this.locked,
    required this.disableAnimations,
    required this.animation,
    required this.child,
  });
  final bool visible;
  final bool locked;
  final bool disableAnimations;
  final Animation<double> animation;
  final Widget child;

  @override
  State<PlayerControlVisibility> createState() =>
      _PlayerControlVisibilityState();
}

class _PlayerControlVisibilityState extends State<PlayerControlVisibility> {
  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_statusChanged);
  }

  void _statusChanged(AnimationStatus status) => setState(() {});

  @override
  void didUpdateWidget(PlayerControlVisibility oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeStatusListener(_statusChanged);
      widget.animation.addStatusListener(_statusChanged);
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_statusChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Visibility(
        visible: !widget.locked &&
            (widget.visible ||
                (!widget.disableAnimations &&
                    widget.animation.status != AnimationStatus.dismissed)),
        child: widget.child,
      );
}
