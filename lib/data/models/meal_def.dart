import "nutrition_plan.dart";

/// Mirrors one entry in the meal database catalog (src/data/mealDatabase.js).
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
    this.notes,
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
  final List<Ingredient> ingredients;
  final String? instructions;
  final String? notes;
  final List<String> dietTags;
  final bool isCustom;
}

/// Mirrors mealDatabase.js `DIET_TAGS` — the real diet-filter taxonomy (raw
/// keys stored on each meal/on client diet filters; `label` is display-only).
const kDietTags = <(String, String)>[
  ("omnivore", "Omnivore / No Restriction"),
  ("vegetarian", "Vegetarian"),
  ("vegan", "Vegan"),
  ("pescatarian", "Pescatarian"),
  ("halal", "Halal"),
  ("kosher", "Kosher"),
  ("no-pork", "No Pork"),
  ("no-beef", "No Beef"),
  ("keto", "Keto"),
  ("paleo", "Paleo"),
  ("high-protein", "High-Protein"),
  ("low-carb", "Low-Carb"),
];

String dietTagLabel(String key) => kDietTags.firstWhere((t) => t.$1 == key, orElse: () => (key, key)).$2;

/// Mirrors mealDatabase.js `INGREDIENT_CATEGORIES` — grocery-list bucketing
/// order/labels.
const kIngredientCategories = <(String, String)>[
  ("proteins", "Proteins"),
  ("vegetables", "Vegetables"),
  ("fruits", "Fruits"),
  ("grains", "Grains & Starches"),
  ("dairy", "Dairy & Alternatives"),
  ("fats", "Healthy Fats"),
  ("pantry", "Pantry Items"),
  ("spices", "Seasonings & Spices"),
  ("beverages", "Beverages"),
];
