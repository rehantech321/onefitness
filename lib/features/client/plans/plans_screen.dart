import "package:flutter/material.dart";
import "../../../core/widgets/widgets.dart";
import "nutrition_tab.dart";
import "workout_tab.dart";

/// Mirrors ClientPlans (ClientNutritionEditor.jsx) — a two-tab view: Workout
/// Program and Nutrition Program. Swipeable via SwipeableTabView — see
/// client_shell.dart's `_swipeOwnedByScreen` for why the shell's own
/// swipe-to-go-back gesture steps aside on this screen.
class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SwipeableTabView(
      labels: ["Workout Program", "Nutrition Program"],
      children: [WorkoutTab(), NutritionTab()],
    );
  }
}
