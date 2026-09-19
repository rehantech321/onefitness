import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../data/providers/trainer_providers.dart";

/// One step of the coach-side back history: which screen was showing, and
/// which client was open at the time — so back can return to *that* client,
/// not just to the Clients screen with whoever happens to be selected now.
typedef _NavEntry = ({String mode, String? clientId});

/// Mirrors App.jsx's `trainerMode` state — which coach-side screen is
/// showing.
///
/// No Navigator route per screen (every destination is just this one
/// string), so hardware back has nothing to pop and would otherwise exit
/// the app. `_history` tracks the path taken to get here so [goBack] can
/// unwind it — see TrainerShell's PopScope.
class TrainerModeNotifier extends Notifier<String> {
  final List<_NavEntry> _history = [];

  @override
  String build() => "dashboard";

  /// True while there's somewhere to go back to. The shell lets the system
  /// back exit the app only when this is false.
  bool get canGoBack => _history.isNotEmpty;

  void _push() {
    _history.add((mode: state, clientId: ref.read(selectedClientIdProvider)));
    // Bounded so a long session can't accumulate an unbounded trail; far
    // beyond anyone's patience for pressing back anyway.
    if (_history.length > 50) _history.removeAt(0);
  }

  void go(String mode) {
    if (mode == state) return;
    // A plain stack: every screen visited is pushed, in order, and back
    // pops one at a time — Page 1 → Page 2 → Page 1 unwinds to Page 2, then
    // Page 1. Dashboard is a page like any other here, not a reset point.
    _push();
    state = mode;
  }

  /// Opens a client's profile — from the roster, Dashboard, Schedule or
  /// anywhere else — as one step back can undo: back returns to the
  /// previous client, or to the screen the client was opened from.
  void openClient(String clientId) {
    if (state == "clients" && ref.read(selectedClientIdProvider) == clientId) return;
    _push();
    ref.read(selectedClientIdProvider.notifier).select(clientId);
    state = "clients";
  }

  void goBack() {
    if (_history.isEmpty) return;
    final entry = _history.removeLast();
    if (entry.clientId != ref.read(selectedClientIdProvider)) {
      ref.read(selectedClientIdProvider.notifier).select(entry.clientId);
    }
    state = entry.mode;
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
