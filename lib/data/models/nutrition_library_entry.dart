import "nutrition_plan.dart";

/// A named, reusable nutrition template — mirrors one entry in the shared
/// "Programs Library" (nutrition side). Workout templates reuse SavedProgram
/// directly since it already carries an id/name; NutritionPlan doesn't, so
/// it needs this thin wrapper.
class NutritionLibraryEntry {
  const NutritionLibraryEntry({required this.id, required this.name, required this.plan});

  final String id;
  final String name;
  final NutritionPlan plan;
}
