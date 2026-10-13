import 'package:flutter/material.dart';

/// An explicit doorway out of a content grid, before geometric traversal can
/// select an unrelated category above it. The app shell owns the rail target.
class TvFocusRailIntent extends Intent {
  const TvFocusRailIntent();
}

/// At a page edge, wrap within the active scope, never into a covered route.
/// Explicit component handlers (player rows / rail / grids) run first.
class TvLoopTraversalPolicy extends ReadingOrderTraversalPolicy {
  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final scope = currentNode.nearestScope;
    final origin = currentNode.rect;
    final previous = scope?.directionalTraversalEdgeBehavior;
    if (scope != null) {
      scope.directionalTraversalEdgeBehavior = TraversalEdgeBehavior.closedLoop;
    }
    try {
      final moved = super.inDirection(currentNode, direction);
      if (moved) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final target = FocusManager.instance.primaryFocus;
          final context = target?.context;
          if (target == null ||
              target == currentNode ||
              context == null ||
              !context.mounted ||
              target.nearestScope != scope ||
              ModalRoute.of(context)?.isCurrent == false) {
            return;
          }
          final rect = target.rect;
          final wrapped = switch (direction) {
            TraversalDirection.down => rect.top < origin.top,
            TraversalDirection.up => rect.bottom > origin.bottom,
            TraversalDirection.right => rect.left < origin.left,
            TraversalDirection.left => rect.right > origin.right,
          };
          if (!wrapped) return;
          // Native directional history predates the jump across the page.
          // Keeping it makes the next opposite arrow skip the final row.
          if (scope != null) invalidateScopeData(scope);
          // Directional traversal reveals only the travelling edge. On a wrap
          // that edge belongs to the opposite end of the viewport, so reveal
          // both edges after the native scroll settles.
          Scrollable.ensureVisible(context,
              alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
          Scrollable.ensureVisible(context,
              alignmentPolicy:
                  ScrollPositionAlignmentPolicy.keepVisibleAtStart);
        });
      }
      return moved;
    } finally {
      if (scope != null && previous != null) {
        scope.directionalTraversalEdgeBehavior = previous;
      }
    }
  }
}

int tvWrappedIndex(int index, int step, int count) =>
    count <= 0 ? 0 : (index + step) % count;

/// Ragged final rows wrap only through real items, never an empty grid cell.
int tvGridTarget(
    int index, int count, int columns, TraversalDirection direction) {
  if (count <= 0) return 0;
  final rowStart = index ~/ columns * columns;
  final rowLength = (count - rowStart).clamp(1, columns);
  final column = index % columns;
  switch (direction) {
    case TraversalDirection.left:
      return rowStart + tvWrappedIndex(column, -1, rowLength);
    case TraversalDirection.right:
      return rowStart + tvWrappedIndex(column, 1, rowLength);
    case TraversalDirection.up:
      return index >= columns
          ? index - columns
          : column + ((count - 1 - column) ~/ columns) * columns;
    case TraversalDirection.down:
      return index + columns < count ? index + columns : column;
  }
}
