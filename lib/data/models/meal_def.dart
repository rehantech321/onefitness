/// Mirrors one entry in the meal database catalog (src/data/mealDatabase.js),
/// trimmed to the fields the coach-facing nutrition builder needs.
class MealDef {
  const MealDef({
    required this.id,
    required this.name,
    required this.mealType, // "breakfast" | "lunch" | "dinner" | "snacks" | "smoothies"
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fats = 0,
    this.ingredients = const [],
    this.instructions,
    this.dietTags = const [],
    this.isCustom = false,
  });

  final String id;
  final String name;
  final String mealType;
  final int calories;
  final double protein;
  final double carbs;
  final double fats;
  final List<String> ingredients;
  final String? instructions;
  final List<String> dietTags;
  final bool isCustom;
}

/// Mirrors constants/domain.js `DIET_TAGS`.
const kDietTags = [
  "High Protein", "Low Carb", "Vegetarian", "Vegan", "Gluten Free", "Dairy Free",
  "Keto", "Paleo", "Quick", "Meal Prep", "Budget", "Kid Friendly",
];
