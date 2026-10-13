import 'package:kazumi/bean/widget/tv_settings_tile_reveal.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/bean/widget/tv_slider_navigation.dart';

import 'package:kazumi/bean/widget/content_section.dart';
import 'package:kazumi/bean/widget/split_list_row.dart';

enum _TileKind { plain, toggle, radio }

class SettingsList extends StatelessWidget {
  const SettingsList({
    super.key,
    required this.sections,
    this.maxWidth = 1000,
  });

  final List<Widget> sections;

  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    Widget section(Widget child) => Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        );
    if (TvMode.enabled) {
      // Settings are bounded, small lists. Keep every section mounted so the
      // remote can traverse and wrap to the actual first/last control rather
      // than the edge of ListView's current cache window.
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(children: sections.map(section).toList()),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: sections.length,
      itemBuilder: (context, index) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: sections[index],
        ),
      ),
    );
  }
}

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.tiles,
    this.title,
    this.bottomInfo,
    this.margin,
  });

  final List<Widget> tiles;
  final Widget? title;
  final Widget? bottomInfo;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: margin ?? const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SectionHeader(title: title!),
            ),
          SplitListGroup(children: tiles),
          if (bottomInfo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: DefaultTextStyle.merge(
                style: textTheme.bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
                child: bottomInfo!,
              ),
            ),
        ],
      ),
    );
  }
}

class SettingsRadioSection<T> extends StatelessWidget {
  const SettingsRadioSection({
    super.key,
    required this.groupValue,
    required this.onChanged,
    required this.tiles,
    this.title,
  });

  final T? groupValue;
  final ValueChanged<T?> onChanged;
  final List<Widget> tiles;
  final Widget? title;

  @override
  Widget build(BuildContext context) {
    final section = SettingsSection(title: title, tiles: tiles);
    if (TvMode.enabled) {
      // Keep desktop RadioGroup traversal away from the focusable TV rows.
      // Each visual indicator below still uses RadioGroup for its value.
      return _TvSettingsRadioScope<T>(
        groupValue: groupValue,
        onChanged: onChanged,
        child: section,
      );
    }
    return RadioGroup<T>(
      groupValue: groupValue,
      onChanged: onChanged,
      child: section,
    );
  }
}

class _TvSettingsRadioScope<T> extends InheritedWidget {
  const _TvSettingsRadioScope({
    required this.groupValue,
    required this.onChanged,
    required super.child,
  });
  final T? groupValue;
  final ValueChanged<T?> onChanged;

  static _TvSettingsRadioScope<T>? maybeOf<T>(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TvSettingsRadioScope<T>>();

  @override
  bool updateShouldNotify(_TvSettingsRadioScope<T> oldWidget) =>
      groupValue != oldWidget.groupValue || onChanged != oldWidget.onChanged;
}

Color _disabledOn(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38);

class _TileLabel extends StatelessWidget {
  const _TileLabel({
    required this.title,
    this.leading,
    this.description,
    this.enabled = true,
  });

  final Widget title;
  final IconData? leading;
  final Widget? description;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final disabled = enabled ? null : _disabledOn(context);
    final foreground = disabled ?? colorScheme.onSurface;
    final secondary = disabled ?? colorScheme.onSurfaceVariant;

    return Row(
      children: [
        if (leading != null) ...[
          Icon(leading, size: 24, color: secondary),
          const SizedBox(width: 16),
        ],
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DefaultTextStyle.merge(
                style: textTheme.bodyLarge?.copyWith(color: foreground),
                child: title,
              ),
              if (description != null) ...[
                const SizedBox(height: 2),
                DefaultTextStyle.merge(
                  style: textTheme.bodySmall?.copyWith(color: secondary),
                  child: description!,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class SettingsCategoryTile extends StatelessWidget {
  const SettingsCategoryTile({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      onHighlightChanged: SplitListRow.pressReporterOf(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 18,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: textTheme.bodyLarge),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: textTheme.bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsSliderTile extends StatelessWidget {
  const SettingsSliderTile({
    super.key,
    required this.title,
    required this.value,
    required this.valueLabel,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.leading,
    this.description,
  });

  final Widget title;
  final IconData? leading;
  final Widget? description;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return TvSettingsTileReveal(
        child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _TileLabel(
                  title: title,
                  leading: leading,
                  description: description,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  valueLabel,
                  style: textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TvSliderNavigation(
              child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            showValueIndicator: ShowValueIndicator.never,
            padding: EdgeInsets.zero,
            onChanged: onChanged,
          )),
        ],
      ),
    ));
  }
}

class SettingsTile<T> extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.title,
    this.leading,
    this.description,
    this.trailing,
    this.value,
    this.onPressed,
    this.enabled = true,
  })  : _kind = _TileKind.plain,
        onToggle = null,
        initialValue = null,
        radioValue = null;

  /// Row taps pass null to [onToggle]; switch gestures pass the new value.
  const SettingsTile.switchTile({
    super.key,
    required this.title,
    required this.initialValue,
    required this.onToggle,
    this.leading,
    this.description,
    this.enabled = true,
  })  : _kind = _TileKind.toggle,
        trailing = null,
        value = null,
        onPressed = null,
        radioValue = null;

  const SettingsTile.radioTile({
    super.key,
    required this.title,
    required T this.radioValue,
    this.leading,
    this.description,
    this.enabled = true,
  })  : _kind = _TileKind.radio,
        trailing = null,
        value = null,
        onPressed = null,
        onToggle = null,
        initialValue = null;

  final Widget title;

  final IconData? leading;
  final Widget? description;
  final Widget? trailing;
  final Widget? value;
  final void Function(BuildContext context)? onPressed;
  final void Function(bool? value)? onToggle;
  final bool? initialValue;
  final T? radioValue;
  final bool enabled;
  final _TileKind _kind;

  VoidCallback? _tapHandler(BuildContext context) {
    if (!enabled) {
      return null;
    }
    switch (_kind) {
      case _TileKind.plain:
        if (onPressed == null &&
            TvMode.enabled &&
            description != null &&
            trailing == null &&
            value == null) {
          // Read-only explanations must be reachable so remote traversal can
          // reveal them below the final interactive setting.
          return () {};
        }
        return onPressed == null ? null : () => onPressed!(context);
      case _TileKind.toggle:
        return onToggle == null ? null : () => onToggle!(null);
      case _TileKind.radio:
        final tvRegistry = _TvSettingsRadioScope.maybeOf<T>(context);
        if (tvRegistry != null) {
          return () => tvRegistry.onChanged(radioValue);
        }
        final registry = RadioGroup.maybeOf<T>(context);
        return registry == null ? null : () => registry.onChanged(radioValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final secondary =
        enabled ? colorScheme.onSurfaceVariant : _disabledOn(context);
    final tvRadioScope = _TvSettingsRadioScope.maybeOf<T>(context);

    return TvSettingsTileReveal(
        child: InkWell(
      onTap: _tapHandler(context),
      onHighlightChanged: SplitListRow.pressReporterOf(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Row(
            children: [
              Expanded(
                child: _TileLabel(
                  title: title,
                  leading: leading,
                  description: description,
                  enabled: enabled,
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 12),
                DefaultTextStyle.merge(
                  style: textTheme.bodyMedium?.copyWith(color: secondary),
                  child: value!,
                ),
              ],
              if (trailing != null) ...[
                const SizedBox(width: 8),
                IconTheme.merge(
                  data: IconThemeData(color: secondary),
                  child: trailing!,
                ),
              ],
              if (_kind == _TileKind.toggle) ...[
                const SizedBox(width: 12),
                // The row owns TV navigation and activation. A second focus
                // target here can trap arrows in RadioGroup or toggle a setting
                // merely while traversing an edge of the page.
                ExcludeFocus(
                  excluding: TvMode.enabled,
                  child: Switch(
                    value: initialValue ?? false,
                    onChanged: enabled ? onToggle : null,
                  ),
                ),
              ],
              if (_kind == _TileKind.radio) ...[
                const SizedBox(width: 12),
                ExcludeFocus(
                  excluding: TvMode.enabled,
                  child: tvRadioScope != null
                      ? RadioGroup<T>(
                          groupValue: tvRadioScope.groupValue,
                          onChanged: tvRadioScope.onChanged,
                          child: Radio<T>(
                              value: radioValue as T, enabled: enabled),
                        )
                      : Radio<T>(value: radioValue as T, enabled: enabled),
                ),
              ],
            ],
          ),
        ),
      ),
    ));
  }
}
