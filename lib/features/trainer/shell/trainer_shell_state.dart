import "package:flutter_riverpod/flutter_riverpod.dart";

/// Mirrors App.jsx's `trainerMode` state — which coach-side screen is showing.
class TrainerModeNotifier extends Notifier<String> {
  @override
  String build() => "dashboard";

  void go(String mode) => state = mode;
}

final trainerModeProvider = NotifierProvider<TrainerModeNotifier, String>(TrainerModeNotifier.new);
