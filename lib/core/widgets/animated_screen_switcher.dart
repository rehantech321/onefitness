import "package:flutter/material.dart";

/// Wraps a shell's content area so switching between destinations (tabs,
/// drawer items, drilling into a sub-screen) gets a soft cross-fade + slight
/// upward slide instead of an instant cut — used by both ClientShell and
/// TrainerShell around their `switch (screen) { ... }` content, so every
/// page-to-page navigation in the app gets the same subtle transition from
/// this one place.
class AnimatedScreenSwitcher extends StatelessWidget {
  const AnimatedScreenSwitcher({
    super.key,
    required this.screenKey,
    required this.child,
  });

  /// Identifies "which screen this is" — changing it (e.g. the shell's
  /// current `screen`/`mode` string) is what triggers the transition.
  final Object screenKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topCenter,
        children: [...previousChildren, if (currentChild != null) currentChild],
      ),
      child: KeyedSubtree(key: ValueKey(screenKey), child: child),
    );
  }
}
