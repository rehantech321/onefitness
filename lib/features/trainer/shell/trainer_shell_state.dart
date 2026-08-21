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

  void go(String mode) {
    if (mode == state) return;
    _history.add(state);
    state = mode;
  }

  void goBack() {
    state = _history.isNotEmpty ? _history.removeLast() : "dashboard";
  }
}

final trainerModeProvider = NotifierProvider<TrainerModeNotifier, String>(
  TrainerModeNotifier.new,
);
