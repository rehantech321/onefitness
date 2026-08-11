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

  static MacroTargets fromJson(Map<String, dynamic>? j) => MacroTargets(
        calories: j?["calories"]?.toString(),
        protein: j?["protein"]?.toString(),
        carbs: j?["carbs"]?.toString(),
        fats: j?["fats"]?.toString(),
        water: j?["water"]?.toString(),
      );
}

/// training/rest split of anything keyed that way (macro targets or
/// per-meal calorie budgets) — mirrors nutritionHelpers.js
/// `getNutritionTargets` / NutritionBuilder.jsx `isSplitMealBudgets`: older
/// saved data has no day split at all, just the training values directly,
/// which is treated as the Training Day entry so nothing already set is lost.
class DaySplit<T> {
  const DaySplit({required this.training, required this.rest});

  final T training;
  final T rest;

  DaySplit<T> copyWith({T? training, T? rest}) => DaySplit(training: training ?? this.training, rest: rest ?? this.rest);
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
/// budgets (also by day type), suggested meals per category, and free-text
/// coach guidelines.
class NutritionPlan {
  const NutritionPlan({
    this.trainingTargets = const MacroTargets(),
    this.restTargets = const MacroTargets(),
    this.mealBudgets = const DaySplit(training: {}, rest: {}),
    this.breakfast = const [],
    this.lunch = const [],
    this.dinner = const [],
    this.snacks = const [],
    this.smoothies = const [],
    this.guidelines,
    this.extraGroceryItems,
  });

  final MacroTargets trainingTargets;
  final MacroTargets restTargets;
  final DaySplit<Map<String, String>> mealBudgets; // day -> breakfast/lunch/dinner/snacks/smoothies -> "kcal"
  final List<NutritionMeal> breakfast;
  final List<NutritionMeal> lunch;
  final List<NutritionMeal> dinner;
  final List<NutritionMeal> snacks;
  final List<NutritionMeal> smoothies;
  final String? guidelines;
  final String? extraGroceryItems;

  NutritionPlan copyWith({
    MacroTargets? trainingTargets,
    MacroTargets? restTargets,
    DaySplit<Map<String, String>>? mealBudgets,
    List<NutritionMeal>? breakfast,
    List<NutritionMeal>? lunch,
    List<NutritionMeal>? dinner,
    List<NutritionMeal>? snacks,
    List<NutritionMeal>? smoothies,
    String? guidelines,
    String? extraGroceryItems,
  }) =>
      NutritionPlan(
        trainingTargets: trainingTargets ?? this.trainingTargets,
        restTargets: restTargets ?? this.restTargets,
        mealBudgets: mealBudgets ?? this.mealBudgets,
        breakfast: breakfast ?? this.breakfast,
        lunch: lunch ?? this.lunch,
        dinner: dinner ?? this.dinner,
        snacks: snacks ?? this.snacks,
        smoothies: smoothies ?? this.smoothies,
        guidelines: guidelines ?? this.guidelines,
        extraGroceryItems: extraGroceryItems ?? this.extraGroceryItems,
      );
}

/// One entry in `client.savedNutritionPrograms` — an AI-drafted or
/// coach-saved calorie/macro target set awaiting review, or already applied.
/// Mirrors generate-ai-nutrition-program's `entry` shape.
class NutritionProgramEntry {
  const NutritionProgramEntry({
    required this.id,
    required this.name,
    required this.status, // "draft" | "active"
    required this.source, // "ai" | "coach"
    required this.trainingTargets,
    required this.restTargets,
    required this.mealBudgets,
    this.guidelines,
    this.createdAt,
    this.createdBy,
  });

  final String id;
  final String name;
  final String status;
  final String source;
  final MacroTargets trainingTargets;
  final MacroTargets restTargets;
  final DaySplit<Map<String, String>> mealBudgets;
  final String? guidelines;
  final String? createdAt;
  final String? createdBy;

  NutritionProgramEntry copyWith({String? status}) => NutritionProgramEntry(
        id: id,
        name: name,
        status: status ?? this.status,
        source: source,
        trainingTargets: trainingTargets,
        restTargets: restTargets,
        mealBudgets: mealBudgets,
        guidelines: guidelines,
        createdAt: createdAt,
        createdBy: createdBy,
      );
}
