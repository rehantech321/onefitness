import "package:flutter_riverpod/flutter_riverpod.dart";

/// Mirrors App.jsx's `trainerMode` state — which coach-side screen is
/// showing.
///
/// No Navigator route per screen (every destination is just this one
/// string), so hardware back has nothing to pop and would otherwise exit
/// the app. `_history` tracks the path taken to get here so [goBack] can
/// unwind it — see TrainerShell's PopScope.
class TrainerModeNotifier extends Notifier<String> {
  final List<String> _history = [];

  @override
  String build() => "dashboard";

  /// True while there's somewhere to go back to. The shell lets the system
  /// back exit the app only when this is false.
  bool get canGoBack => _history.isNotEmpty;

  void go(String mode) {
    if (mode == state) return;
    // A plain stack: every screen visited is pushed, in order, and back
    // pops one at a time — Page 1 → Page 2 → Page 1 unwinds to Page 2, then
    // Page 1. Dashboard is a page like any other here, not a reset point.
    _history.add(state);
    // Bounded so a long session can't accumulate an unbounded trail; far
    // beyond anyone's patience for pressing back anyway.
    if (_history.length > 50) _history.removeAt(0);
    state = mode;
  }

  void goBack() {
    if (_history.isEmpty) return;
    state = _history.removeLast();
  }

  /// A fresh staff session starts on Dashboard with no trail behind it.
  void reset() {
    _history.clear();
    state = "dashboard";
  }
}

final trainerModeProvider = NotifierProvider<TrainerModeNotifier, String>(
  TrainerModeNotifier.new,
);
