import 'dart:async';

import 'package:flutter/material.dart';

enum TvHomeFocusKind { category, poster, recent }

/// Runtime identity for home navigation. Flutter strips FocusNode.debugLabel
/// from release builds, so labels are never used to select a control.
@immutable
class TvHomeFocusIdentity {
  const TvHomeFocusIdentity.category(this.category)
      : kind = TvHomeFocusKind.category,
        subjectId = null,
        channelNumber = null;
  const TvHomeFocusIdentity.poster(
      {required this.subjectId, required this.channelNumber})
      : kind = TvHomeFocusKind.poster,
        category = null;
  const TvHomeFocusIdentity.recent(this.subjectId)
      : kind = TvHomeFocusKind.recent,
        category = null,
        channelNumber = null;
  final TvHomeFocusKind kind;
  final String? category;
  final int? subjectId;
  final int? channelNumber;
}

/// The routed home draws the shell's function group beside its categories.
/// Other routed pages draw the same group above their content.
class TvDesktopNavigation extends InheritedWidget {
  const TvDesktopNavigation({
    super.key,
    required this.functionBar,
    this.onHomeReady,
    required super.child,
  });
  final WidgetBuilder functionBar;
  final ValueChanged<FocusNode>? onHomeReady;
  static final _homeFocusIdentities =
      Expando<TvHomeFocusIdentity>('tv-home-focus');

  static FocusNode registerHomeFocus(
      FocusNode node, TvHomeFocusIdentity identity) {
    _homeFocusIdentities[node] = identity;
    return node;
  }

  static TvHomeFocusIdentity? homeFocusOf(FocusNode node) =>
      _homeFocusIdentities[node];
  static const startupTraceEnabled =
      bool.fromEnvironment('KAZUMI_FUSION_UI_TRACE');
  static int _startupTraceEvents = 0;

  /// A diagnostic build can log at most ten route/focus handoff events. Normal
  /// builds compile this out; no artwork, subjects, storage, or FFI is read.
  static void traceStartupFocus(
    String event, {
    FocusNode? focus,
    bool? pending,
    int? epoch,
    bool? current,
    bool? covered,
    bool? attached,
    bool? canFocus,
  }) {
    if (!startupTraceEnabled || _startupTraceEvents >= 10) return;
    final sequence = ++_startupTraceEvents;
    final label = focus?.debugLabel ?? focus?.runtimeType.toString() ?? 'none';
    final message = '[KAZUMI_FUSION_UI_TRACE] $sequence $event '
        'focus=$label pending=$pending epoch=$epoch current=$current '
        'covered=$covered attached=$attached canFocus=$canFocus';
    scheduleMicrotask(() => debugPrint(message));
  }

  static TvDesktopNavigation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TvDesktopNavigation>();
  @override
  bool updateShouldNotify(TvDesktopNavigation oldWidget) => true;
}
