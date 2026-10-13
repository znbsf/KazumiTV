import 'package:flutter/material.dart';
import 'package:kazumi/services/storage/storage.dart';

/// Only decorative shortcut hints belong here, never actual channel numbers,
/// episode numbers or entered digits. Listening changes presentation only.
class NumericShortcutVisibility extends StatelessWidget {
  const NumericShortcutVisibility({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => StreamBuilder<void>(
        stream:
            GStorage.watchSettings([SettingsKeys.showNumericShortcutBadges]),
        builder: (context, _) =>
            GStorage.getSetting(SettingsKeys.showNumericShortcutBadges)
                ? child
                : const SizedBox.shrink(),
      );
}
