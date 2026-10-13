import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

/// Settings rows open their menu programmatically, outside MenuAnchor's child.
/// Give TV menus focus and a route-local Back entry, then restore the row.
class TvSettingsMenuAnchor extends StatefulWidget {
  const TvSettingsMenuAnchor(
      {super.key,
      this.controller,
      this.style,
      required this.menuChildren,
      required this.builder,
      this.consumeOutsideTap = true});
  final MenuController? controller;
  final MenuStyle? style;
  final List<Widget> menuChildren;
  final MenuAnchorChildBuilder builder;
  final bool consumeOutsideTap;
  @override
  State<TvSettingsMenuAnchor> createState() => _TvSettingsMenuAnchorState();
}

class _TvSettingsMenuAnchorState extends State<TvSettingsMenuAnchor> {
  final _ownedController = MenuController();
  MenuController get _controller => widget.controller ?? _ownedController;
  final _menuFocus = FocusScopeNode(debugLabel: 'TV settings menu');
  FocusNode? _returnFocus;
  final _history = <LocalHistoryEntry>[];

  void _opened() {
    _returnFocus = FocusManager.instance.primaryFocus;
    // Direct settings entry dispatches Back to the host, while a pushed
    // pane can receive it through the nested Navigator. Whichever handles
    // Back first closes the menu and removes its counterpart's history.
    final host =
        context.getElementForInheritedWidgetOfExactType<SettingsPaneScope>();
    final routes = <ModalRoute<dynamic>>{
      if (ModalRoute.of(context) case final route?) route,
      if (ModalRoute.of(host ?? context) case final route?) route,
    };
    for (final route in routes) {
      late final LocalHistoryEntry entry;
      entry = LocalHistoryEntry(onRemove: () {
        if (!_history.remove(entry)) return;
        if (_controller.isOpen) _controller.close();
      });
      _history.add(entry);
      route.addLocalHistoryEntry(entry);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.isOpen) return;
      for (final node in _menuFocus.traversalDescendants) {
        if (node is! FocusScopeNode && node.canRequestFocus) {
          node.requestFocus();
          break;
        }
      }
    });
  }

  void _clearHistory() {
    final entries = _history.toList();
    _history.clear();
    for (final entry in entries) {
      entry.remove();
    }
  }

  void _closed() {
    _clearHistory();
    final target = _returnFocus;
    _returnFocus = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && target?.context != null && target!.canRequestFocus) {
        target.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _clearHistory();
    _menuFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MenuAnchor(
        controller: _controller,
        style: widget.style,
        consumeOutsideTap: widget.consumeOutsideTap,
        builder: widget.builder,
        onOpen: TvMode.enabled ? _opened : null,
        onClose: TvMode.enabled ? _closed : null,
        menuChildren: TvMode.enabled
            ? [
                FocusScope(
                    node: _menuFocus,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: widget.menuChildren,
                    )),
              ]
            : widget.menuChildren,
      );
}
