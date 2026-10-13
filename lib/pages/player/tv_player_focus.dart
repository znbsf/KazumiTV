import 'package:flutter/material.dart';

/// Panel timers may finish after a sheet/dialog has covered the player.
/// Only the visible player route may reclaim remote input.
bool requestPlayerFocusIfCurrent(BuildContext context, FocusNode target) {
  if (!context.mounted || ModalRoute.of(context)?.isCurrent != true)
    return false;
  target.requestFocus();
  return true;
}
