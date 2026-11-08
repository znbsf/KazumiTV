import 'package:flutter/material.dart';

/// Supplies focus once for a TV dialog whose descendants have no autofocus.
/// Callers insert this only in TV mode, leaving other widget trees unchanged.
class TvDialogInitialFocus extends StatefulWidget {
  const TvDialogInitialFocus({super.key, required this.child});

  final Widget child;

  @override
  State<TvDialogInitialFocus> createState() => _TvDialogInitialFocusState();
}

class _TvDialogInitialFocusState extends State<TvDialogInitialFocus> {
  @override
  void initState() {
    super.initState();
    _focusInitial();
  }

  Future<void> _focusInitial() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    FocusManager.instance.applyFocusChangesIfNeeded();
    final scope = FocusScope.of(context);
    if (scope.focusedChild == null) scope.nextFocus();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
