import 'dart:async';

import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/widget/tv_player_side_panel.dart';
import 'package:kazumi/bean/widget/tv_visuals.dart';
import 'package:kazumi/bean/widget/tv_focus_label.dart';
import 'package:scrollview_observer/scrollview_observer.dart';

/// Native main's compact player action, with one target for remote and pointer.
class TvPlayerAction extends StatefulWidget {
  const TvPlayerAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.focusNode,
    this.autofocus = false,
    this.selected = false,
    this.iconBuilder,
  });

  final String label;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool selected;
  final Widget Function(Color color)? iconBuilder;

  @override
  State<TvPlayerAction> createState() => _TvPlayerActionState();
}

class _TvPlayerActionState extends State<TvPlayerAction> {
  bool _focused = false;

  void _onFocusChange(bool focused) {
    setState(() => _focused = focused);
    if (!focused) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focused) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 160),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final scheme = Theme.of(context).colorScheme;
    final color = !enabled
        ? Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: .5)
        : _focused
            ? scheme.onPrimary
            : widget.selected
                ? scheme.onSecondaryContainer
                : scheme.onSurface;
    final iconOnly = widget.iconBuilder != null;
    final action = Semantics(
      label: iconOnly ? widget.label : null,
      button: true,
      enabled: enabled,
      selected: widget.selected,
      child: Focus(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        canRequestFocus: enabled,
        descendantsAreFocusable: false,
        descendantsAreTraversable: false,
        onFocusChange: _onFocusChange,
        onKeyEvent: (node, event) {
          if (!enabled || event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter ||
              key == LogicalKeyboardKey.gameButtonA ||
              key == LogicalKeyboardKey.space) {
            widget.onPressed!();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Material(
          color: enabled && _focused
              ? scheme.primary
              : enabled && widget.selected
                  ? scheme.secondaryContainer
                  : scheme.surface.withValues(alpha: .94),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
                color: enabled && _focused
                    ? scheme.onSurface
                    : enabled && widget.selected
                        ? scheme.secondary
                        : Colors.transparent,
                width: enabled && _focused ? 3 : 1),
          ),
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: 38,
                minWidth: iconOnly ? 38 : 0,
              ),
              child: Padding(
                padding: iconOnly
                    ? const EdgeInsets.all(7)
                    : const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Align(
                  alignment: iconOnly ? Alignment.center : Alignment.centerLeft,
                  widthFactor: 1,
                  heightFactor: 1,
                  child: iconOnly
                      ? widget.iconBuilder!(color)
                      : Text(
                          widget.label,
                          style: TvVisuals.control.copyWith(color: color),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return iconOnly
        ? TvFocusLabel(
            message: widget.label,
            child: Tooltip(
              message: widget.label,
              excludeFromSemantics: true,
              child: action,
            ))
        : action;
  }
}

/// Reads playback state supplied by Dart; never accesses native diagnostics.
class TvPlayerProgress extends StatefulWidget {
  const TvPlayerProgress({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onSeek,
    required this.focusNode,
    this.step = const Duration(seconds: 10),
    this.onVerticalKey,
    this.onDragStart,
    this.onDragUpdate,
  });

  final Duration position;
  final Duration duration;
  final Duration buffered;
  final Duration step;
  final FutureOr<void> Function(Duration) onSeek;
  final FocusNode focusNode;
  final VoidCallback? onVerticalKey;
  final VoidCallback? onDragStart;
  final ValueChanged<Duration>? onDragUpdate;

  @override
  State<TvPlayerProgress> createState() => _TvPlayerProgressState();
}

class _TvPlayerProgressState extends State<TvPlayerProgress> {
  bool _focused = false;

  void _seekBy(int direction) {
    if (widget.duration <= Duration.zero) return;
    final milliseconds = (widget.position.inMilliseconds +
            direction * widget.step.inMilliseconds)
        .clamp(0, widget.duration.inMilliseconds)
        .toInt();
    unawaited(
      Future<void>.sync(
        () => widget.onSeek(Duration(milliseconds: milliseconds)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: '播放进度，左右快进退${widget.step.inSeconds}秒',
        child: Focus(
          focusNode: widget.focusNode,
          descendantsAreFocusable: false,
          onFocusChange: (focused) => setState(() => _focused = focused),
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                event.logicalKey == LogicalKeyboardKey.arrowRight) {
              _seekBy(
                  event.logicalKey == LogicalKeyboardKey.arrowRight ? 1 : -1);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                event.logicalKey == LogicalKeyboardKey.arrowDown) {
              widget.onVerticalKey?.call();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: SizedBox(
            height: 24,
            child: Center(
              child: ProgressBar(
                progress: widget.position,
                total: widget.duration,
                buffered: widget.buffered,
                progressBarColor: Theme.of(context).colorScheme.primary,
                baseBarColor: Colors.white.withValues(alpha: .18),
                bufferedBarColor: Colors.white.withValues(alpha: .4),
                thumbColor: Theme.of(context).colorScheme.primary,
                barHeight: _focused ? 5 : 3,
                thumbRadius: _focused ? 7 : 4,
                thumbGlowRadius: 14,
                timeLabelLocation: TimeLabelLocation.none,
                onSeek: widget.onSeek,
                onDragStart: (_) => widget.onDragStart?.call(),
                onDragUpdate: (details) =>
                    widget.onDragUpdate?.call(details.timeStamp),
              ),
            ),
          ),
        ),
      );
}

/// Presented in an owned dialog route so Back cannot reach playback controls.
class TvPlayerSettingsPanel extends StatefulWidget {
  const TvPlayerSettingsPanel({
    super.key,
    required this.title,
    required this.onBack,
    required this.children,
    this.initialFocusNode,
    this.initialFocusIndex,
  });

  final String title;
  final VoidCallback onBack;
  final List<Widget> children;
  final FocusNode? initialFocusNode;
  final int? initialFocusIndex;

  @override
  State<TvPlayerSettingsPanel> createState() => _TvPlayerSettingsPanelState();
}

class _TvPlayerSettingsPanelState extends State<TvPlayerSettingsPanel> {
  final _scope = FocusScopeNode(debugLabel: 'Player settings');
  final _backFocus = FocusNode(debugLabel: 'Player settings back');
  final _scroll = ScrollController();
  late final _observer = ListObserverController(controller: _scroll);

  @override
  void initState() {
    super.initState();
    unawaited(_focusInitial());
  }

  Future<void> _focusInitial() async {
    // Resume after all first-frame callbacks, including the observer's sliver
    // registration, instead of jumping from the parent's earlier callback.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scroll.hasClients) return;
    final selectedIndex = widget.children.indexWhere((child) =>
        child is TvPlayerAction && child.selected && child.onPressed != null);
    final firstIndex = widget.children.indexWhere(
        (child) => child is TvPlayerAction && child.onPressed != null);
    final index = widget.initialFocusIndex ??
        (selectedIndex >= 0 ? selectedIndex : firstIndex);
    if (index >= 0) {
      // Title, gap, Back, then alternating gaps and business controls.
      final positioned = _observer.jumpTo(index: 4 + index * 2);
      // The observer completes after a frame even when no scrolling is needed.
      WidgetsBinding.instance.scheduleFrame();
      await positioned;
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final items = _scope.traversalDescendants.where((node) =>
          node is! FocusScopeNode &&
          node != _backFocus &&
          node.context?.findAncestorWidgetOfExactType<TvPlayerAction>() !=
              null &&
          node.canRequestFocus);
      final selected = items.where((node) =>
          node.context
              ?.findAncestorWidgetOfExactType<TvPlayerAction>()
              ?.selected ==
          true);
      final target = widget.initialFocusNode ??
          selected.firstOrNull ??
          items.firstOrNull ??
          _backFocus;
      target.requestFocus();
      final targetContext = target.context;
      if (targetContext != null) {
        // The observer jump builds the target but can leave its bottom clipped.
        unawaited(Scrollable.ensureVisible(
          targetContext,
          alignment: .5,
          duration: Duration.zero,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        ));
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _backFocus.dispose();
    _scope.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width.clamp(0, 340).toDouble(),
          height: double.infinity,
          child: TvPlayerSidePanel(
            opacity: 1,
            child: FocusScope(
              node: _scope,
              child: FocusTraversalGroup(
                policy: WidgetOrderTraversalPolicy(),
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        (event.logicalKey == LogicalKeyboardKey.escape ||
                            event.logicalKey == LogicalKeyboardKey.goBack ||
                            event.logicalKey ==
                                LogicalKeyboardKey.gameButtonB)) {
                      widget.onBack();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: ListViewObserver(
                    controller: _observer,
                    child: ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.all(28),
                      children: [
                        Text(
                          widget.title,
                          style: TvVisuals.title.copyWith(
                              color: Theme.of(context).colorScheme.onSurface),
                        ),
                        const SizedBox(height: 12),
                        TvPlayerAction(
                          focusNode: _backFocus,
                          label: widget.title == '设置' ? '返回播放' : '返回设置',
                          onPressed: widget.onBack,
                        ),
                        for (final child in widget.children) ...[
                          const SizedBox(height: 12),
                          child,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
