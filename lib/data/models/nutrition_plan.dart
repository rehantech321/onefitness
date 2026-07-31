/// One macro target set (calories/protein%/carbs%/fats%/water) for either a
/// training or rest day — mirrors nutritionHelpers.js `getNutritionTargets`.
class MacroTargets {
  const MacroTargets({this.calories, this.protein, this.carbs, this.fats, this.water});

  final String? calories;
  final String? protein;
  final String? carbs;
  final String? fats;
  final String? water;

  Map<String, String?> asMap() => {
        "calories": calories,
        "protein": protein,
        "carbs": carbs,
        "fats": fats,
        "water": water,
      };
}

/// One grocery ingredient line under a meal.
class Ingredient {
  const Ingredient({required this.item, this.qty, this.unit});
  final String item;
  final num? qty;
  final String? unit;
}

/// One suggested meal (breakfast/lunch/dinner/snack/smoothie) — mirrors the
/// meal shape read by NutritionScreenReadOnly.jsx's NutritionSuggestionList.
class NutritionMeal {
  const NutritionMeal({
    required this.id,
    required this.name,
    this.time,
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fats = 0,
    this.ingredients = const [],
    this.notes,
  });

  final String id;
  final String name;
  final String? time;
  final int calories;
  final double protein;
  final double carbs;
  final double fats;
  final List<Ingredient> ingredients;
  final String? notes;
}

/// Mirrors the legacy flat `client.nutrition` shape read by
/// NutritionScreenReadOnly.jsx — targets by day type, per-meal calorie
/// budgets, suggested meals per category, and free-text coach guidelines.
class NutritionPlan {
  const NutritionPlan({
    this.trainingTargets = const MacroTargets(),
    this.restTargets = const MacroTargets(),
    this.mealBudgets = const {},
    this.breakfast = const [],
    this.lunch = const [],
    this.dinner = const [],
    this.snacks = const [],
    this.smoothies = const [],
    this.guidelines,
  });

  final MacroTargets trainingTargets;
  final MacroTargets restTargets;
  final Map<String, String> mealBudgets; // breakfast/lunch/dinner/snacks/smoothies -> "kcal"
  final List<NutritionMeal> breakfast;
  final List<NutritionMeal> lunch;
  final List<NutritionMeal> dinner;
  final List<NutritionMeal> snacks;
  final List<NutritionMeal> smoothies;
  final String? guidelines;
}
