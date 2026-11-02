import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../data/providers/theme_mode_provider.dart";
import "app_colors.dart";
import "app_theme.dart";

/// Installs the active palette and repaints the screens already on screen
/// when it changes.
///
/// Wraps the app's MaterialApp, and hands [builder] the matching ThemeData.
///
/// ── The problem this solves ─────────────────────────────────────────────
/// [AppColors]' tokens are plain static getters over one global palette.
/// That is what lets ~170 screens re-theme without being rewritten to read
/// `Theme.of(context)` — but it also means a widget painting itself gold has
/// no dependency Flutter can track: no InheritedWidget, no provider. Swapping
/// the palette changes what the getters return and schedules no rebuild.
///
/// Rebuilding the root doesn't help either, because `Element.updateChild`
/// short-circuits when a child's widget instance is identical — and the app's
/// screens are overwhelmingly `const`. Propagation stops at the first one.
///
/// The symptom was a theme change appearing only on the *next* screen opened:
/// the one in front of you kept its old colours until something unrelated
/// rebuilt it.
///
/// ── Why it marks elements dirty rather than changing a key ──────────────
/// A ValueKey on the subtree would also force a repaint, by destroying and
/// recreating every element below it — taking the navigation stack, scroll
/// positions, and any half-typed intake form or in-progress set log with it.
/// A dirty element rebuilds in place and keeps its State, so switching to
/// dark mid-workout costs a frame and nothing else. It is the same mechanism
/// hot reload uses to repaint a running app without restarting it.
class PaletteScope extends ConsumerStatefulWidget {
  const PaletteScope({super.key, required this.builder});

  /// Builds the app below this scope, given the theme for the live palette.
  final Widget Function(BuildContext context, ThemeData theme) builder;

  @override
  ConsumerState<PaletteScope> createState() => _PaletteScopeState();
}

class _PaletteScopeState extends ConsumerState<PaletteScope> {
  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);
    // "Match phone" is resolved here rather than by handing MaterialApp both
    // a light and a dark theme, because AppColors is a single global: there
    // is only ever one active palette, and it has to be the one MaterialApp
    // is about to use.
    //
    // Applied directly instead of through AppTheme.themeFor so that the
    // "did it actually change" answer is visible.
    final changed = AppColors.apply(
      AppTheme.paletteFor(mode, MediaQuery.platformBrightnessOf(context)),
    );
    if (changed) {
      // Not during this build: marking elements dirty mid-build is illegal,
      // and the screens below have to finish this frame before being asked
      // for another.
      WidgetsBinding.instance.addPostFrameCallback((_) => _repaintSubtree());
    }
    return widget.builder(context, AppTheme.current);
  }

  void _repaintSubtree() {
    if (!mounted) return;
    void markDirty(Element element) {
      element.markNeedsBuild();
      element.visitChildren(markDirty);
    }

    // From the children down. This element has just built and the palette is
    // already applied, so a repeat pass finds nothing changed and schedules
    // no further work — which is what stops this recursing.
    (context as Element).visitChildren(markDirty);
  }
}
