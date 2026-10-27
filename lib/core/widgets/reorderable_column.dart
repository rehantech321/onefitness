import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "../theme/app_colors.dart";

/// A short list that reorders by press-and-hold, inside a page that already
/// scrolls.
///
/// Every reorderable list in this app sits in a `SingleChildScrollView` — the
/// Access Hub's categories and plans, a program's days and exercises, the
/// custom profile fields. That ruled out an ordinary drag handle, because a
/// handle grabs the drag the instant a finger lands on it, and on a phone the
/// same gesture is how you scroll the page you're standing on. Those screens
/// used up/down arrows instead.
///
/// [ReorderableDelayedDragStartListener] is what resolves that: a swipe still
/// scrolls, and only a press held for [kLongPressTimeout] begins a drag. The
/// two gestures stop competing because they're no longer the same gesture.
///
/// The list itself never scrolls ([NeverScrollableScrollPhysics] with
/// `shrinkWrap`) — the page around it does. The one thing that costs is
/// auto-scroll while dragging: an item can't be dragged past the edge of the
/// screen to move it somewhere out of view. For lists of a handful of items,
/// which is all of these, every position is on screen anyway.
class ReorderableColumn extends StatelessWidget {
  const ReorderableColumn({
    super.key,
    required this.itemCount,
    required this.keyOf,
    required this.itemBuilder,
    required this.onReorder,
    this.enabled = true,
    this.padding,
  });

  final int itemCount;

  /// A stable identity per item — the row's own id, never its index. A key
  /// derived from position would be the same key before and after a move, and
  /// the list would animate the wrong row.
  final String Function(int index) keyOf;

  final Widget Function(BuildContext context, int index) itemBuilder;

  /// Called with indices already normalised: move the item at [oldIndex] so
  /// it sits at [newIndex] in the resulting list. Never called for a no-op.
  final void Function(int oldIndex, int newIndex) onReorder;

  /// False while there's nothing to reorder (a single item, or a list the
  /// caller has locked), so a long-press doesn't lift something that can't
  /// go anywhere.
  final bool enabled;

  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: padding ?? EdgeInsets.zero,
      // The built-in handle is the thing this widget exists to avoid; each
      // item supplies its own press-and-hold listener below.
      buildDefaultDragHandles: false,
      itemCount: itemCount,
      // Confirms the hold registered, at the moment the item lifts. Without
      // it a long-press is invisible until the finger moves, and it reads as
      // nothing having happened.
      onReorderStart: (_) => HapticFeedback.mediumImpact(),
      onReorder: (oldIndex, newIndex) {
        // ReorderableListView reports the target as an index in the list
        // *before* the dragged item is taken out, so every downward move is
        // off by one until this is applied.
        if (newIndex > oldIndex) newIndex -= 1;
        if (newIndex == oldIndex) return;
        onReorder(oldIndex, newIndex);
      },
      proxyDecorator: (child, index, animation) => _LiftedItem(animation: animation, child: child),
      itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
        key: ValueKey(keyOf(i)),
        index: i,
        enabled: enabled,
        child: itemBuilder(context, i),
      ),
    );
  }
}

/// How an item looks while it's being carried.
///
/// Replaces the framework's default, which drops a Material elevation shadow
/// — invisible against this app's near-black surfaces, so a dragged row would
/// look identical to a stationary one. A gold edge and a slight lift read on
/// a dark background.
class _LiftedItem extends StatelessWidget {
  const _LiftedItem({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeOut.transform(animation.value);
        return Transform.scale(
          scale: 1 + (0.03 * t),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.55 * t)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45 * t),
                    blurRadius: 16 * t,
                    offset: Offset(0, 4 * t),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
