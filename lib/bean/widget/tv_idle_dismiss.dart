import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/services/platform/app_remote.dart';

/// Inactivity belongs to this visible panel, never to a covered dialog or page.
class TvIdleDismiss extends StatefulWidget {
  const TvIdleDismiss(
      {super.key,
      required this.child,
      required this.enabled,
      required this.onDismiss});
  final Widget child;
  final bool enabled;
  final VoidCallback onDismiss;
  @override
  State<TvIdleDismiss> createState() => _TvIdleDismissState();
}

class _TvIdleDismissState extends State<TvIdleDismiss>
    with WidgetsBindingObserver {
  Timer? _timer;
  ModalRoute<dynamic>? _route;
  bool _foreground = true;
  bool get _active =>
      mounted && widget.enabled && _foreground && _route?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    AppRemote.instance.activity.addListener(_reset);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _reset();
  }

  @override
  void didUpdateWidget(covariant TvIdleDismiss oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _reset();
  }

  bool _onKey(KeyEvent event) {
    _reset();
    return false;
  }

  void _reset() {
    _timer?.cancel();
    _timer = null;
    if (!_active) return;
    _timer = Timer(const Duration(seconds: 3), () {
      if (_active) widget.onDismiss();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _reset();
  }

  @override
  void dispose() {
    _timer?.cancel();
    AppRemote.instance.activity.removeListener(_reset);
    HardwareKeyboard.instance.removeHandler(_onKey);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _reset(),
      onPointerMove: (_) => _reset(),
      onPointerUp: (_) => _reset(),
      onPointerHover: (_) => _reset(),
      onPointerSignal: (_) => _reset(),
      child: widget.child);
}
