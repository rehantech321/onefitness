import "package:flutter_test/flutter_test.dart";

import "package:onefitness/data/mock/meal_catalog.dart";

/// Clients choose their own meals for every category after a nutrition
/// program is generated — breakfast, lunch, dinner, snacks and smoothies.
/// The picker filters the catalogue by `mealType`, so a category with no
/// meals behind it would open an empty sheet.
void main() {
  test("the catalogue covers every category the client can pick from", () {
    const categories = ["breakfast", "lunch", "dinner", "snacks", "smoothies"];
    for (final c in categories) {
      final available = kMealCatalog.where((m) => m.mealType == c).toList();
      expect(
        available,
        isNotEmpty,
        reason: "'$c' is offered in the nutrition tab, so the picker needs "
            "meals of that type or it opens empty",
      );
    }
  });

  test("meal types are exactly the five the UI offers — no orphans", () {
    final types = kMealCatalog.map((m) => m.mealType).toSet();
    expect(
      types,
      {"breakfast", "lunch", "dinner", "snacks", "smoothies"},
      reason: "a type in the catalogue with no section in the nutrition tab "
          "is unreachable, and a section with no type opens empty",
    );
  });

  test("every catalogue meal has calories, so budget matching works", () {
    final noCalories = kMealCatalog.where((m) => m.calories <= 0).toList();
    expect(
      noCalories.map((m) => m.name).toList(),
      isEmpty,
      reason: "the picker sorts and filters by closeness to the meal's "
          "calorie budget; a zero-calorie entry can never match one",
    );
  });
}
