import 'package:flutter/material.dart';

/// A back stack inside one modal route, deliberately without a nested Navigator.
/// Back/maybePop returns to the previous page; explicit Navigator.pop (including
/// a final result or a close button) still ends the entire modal flow.
class TvPanelPageHost extends StatefulWidget {
  const TvPanelPageHost({super.key, required this.builder});

  final WidgetBuilder builder;

  static TvPanelPageHostState of(BuildContext context) =>
      context.findAncestorStateOfType<TvPanelPageHostState>()!;

  @override
  State<TvPanelPageHost> createState() => TvPanelPageHostState();
}

class TvPanelPageHostState extends State<TvPanelPageHost> {
  late final _pages = <_PanelPageEntry>[_PanelPageEntry(widget.builder)];

  void push(WidgetBuilder builder) {
    final entry = _PanelPageEntry(builder,
        returnFocus: FocusManager.instance.primaryFocus);
    setState(() => _pages.add(entry));
  }

  void _back() {
    final entry = _pages.last;
    setState(() => _pages.removeLast());
    final parent = _pages.last;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The parent must rebuild with focus enabled before restoring its entry.
      if (!mounted || _pages.last != parent) return;
      parent.key.currentState?.restoreFocus(entry.returnFocus);
    });
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
        canPop: _pages.length == 1,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _pages.length > 1) _back();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            for (final entry in _pages)
              Offstage(
                key: ObjectKey(entry),
                offstage: entry != _pages.last,
                child: TickerMode(
                  enabled: entry == _pages.last,
                  child: _PanelPage(
                    key: entry.key,
                    active: entry == _pages.last,
                    builder: entry.builder,
                  ),
                ),
              ),
          ],
        ),
      );
}

class _PanelPageEntry {
  _PanelPageEntry(this.builder, {this.returnFocus});
  final key = GlobalKey<_PanelPageState>();
  final WidgetBuilder builder;
  final FocusNode? returnFocus;
}

class _PanelPage extends StatefulWidget {
  const _PanelPage({super.key, required this.active, required this.builder});
  final bool active;
  final WidgetBuilder builder;

  @override
  State<_PanelPage> createState() => _PanelPageState();
}

class _PanelPageState extends State<_PanelPage> {
  final _scope = FocusScopeNode(debugLabel: 'TV modal page');

  @override
  void initState() {
    super.initState();
    _focusInitial();
  }

  Future<void> _focusInitial() async {
    // Let descendants' autofocus requests settle before supplying a fallback.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !widget.active) return;
    FocusManager.instance.applyFocusChangesIfNeeded();
    if (_scope.focusedChild == null) _scope.nextFocus();
  }

  void restoreFocus(FocusNode? returnFocus) {
    if (!mounted || !widget.active) return;
    final returnContext = returnFocus?.context;
    final target = returnFocus != null &&
            returnContext != null &&
            returnContext.mounted &&
            returnFocus.canRequestFocus &&
            returnFocus.ancestors.contains(_scope)
        ? returnFocus
        : FocusTraversalGroup.of(_scope.context!)
            .findFirstFocus(_scope, ignoreCurrentFocus: true);
    target?.requestFocus();
    final targetContext = target?.context;
    if (targetContext != null && targetContext.mounted) {
      Scrollable.ensureVisible(targetContext, duration: Duration.zero);
    }
  }

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeFocus(
        excluding: !widget.active,
        child: FocusScope(
          node: _scope,
          // Keep the node's own flag enabled; ExcludeFocus gates the whole page.
          canRequestFocus: true,
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: double.infinity,
              child: Builder(builder: widget.builder),
            ),
          ),
        ),
      );
}
