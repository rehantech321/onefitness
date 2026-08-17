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

/// Per-ONE-unit macro density for an ingredient — mirrors mealDatabase.js
/// `ingM`'s macros arg ({cals, p, c, f}), used to recompute a meal's totals
/// live as quantities change (computeMacrosFromIngredients).
class IngredientMacros {
  const IngredientMacros({required this.cals, required this.p, required this.c, required this.f});

  final double cals;
  final double p;
  final double c;
  final double f;

  static IngredientMacros? fromJson(dynamic j) => j is Map
      ? IngredientMacros(
          cals: (j["cals"] as num?)?.toDouble() ?? 0,
          p: (j["p"] as num?)?.toDouble() ?? 0,
          c: (j["c"] as num?)?.toDouble() ?? 0,
          f: (j["f"] as num?)?.toDouble() ?? 0,
        )
      : null;

  Map<String, dynamic> toJson() => {"cals": cals, "p": p, "c": c, "f": f};
}

/// One grocery ingredient line under a meal — mirrors mealDatabase.js
/// `ing`/`ingM` output. `category` drives grocery-list bucketing
/// (INGREDIENT_CATEGORIES); `macros` (per one unit) is present on every
/// built-in catalog ingredient and drives live macro recalculation as a
/// coach adjusts quantities.
class Ingredient {
  const Ingredient({required this.item, this.qty, this.unit, this.category, this.macros});

  final String item;
  final num? qty;
  final String? unit;
  final String? category;
  final IngredientMacros? macros;

  Ingredient copyWith({num? qty, bool clearQty = false}) =>
      Ingredient(item: item, qty: clearQty ? null : (qty ?? this.qty), unit: unit, category: category, macros: macros);

  static Ingredient fromJson(Map<String, dynamic> j) => Ingredient(
        item: j["item"] as String? ?? "",
        qty: j["qty"] as num?,
        unit: j["unit"] as String?,
        category: j["category"] as String?,
        macros: IngredientMacros.fromJson(j["macros"]),
      );

  Map<String, dynamic> toJson() => {
        "item": item,
        "qty": qty,
        "unit": unit,
        "category": category,
        if (macros != null) "macros": macros!.toJson(),
      };
}

/// A meal's totals after scaling to a calorie target — mirrors
/// nutritionHelpers.js `scaleMeal`'s `scaledMacros` / `effectiveMacros`'s
/// return shape.
class MacroSnapshot {
  const MacroSnapshot({required this.calories, required this.protein, required this.carbs, required this.fats});

  final int calories;
  final double protein;
  final double carbs;
  final double fats;

  static MacroSnapshot? fromJson(dynamic j) => j is Map
      ? MacroSnapshot(
          calories: (j["calories"] as num?)?.round() ?? 0,
          protein: (j["protein"] as num?)?.toDouble() ?? 0,
          carbs: (j["carbs"] as num?)?.toDouble() ?? 0,
          fats: (j["fats"] as num?)?.toDouble() ?? 0,
        )
      : null;

  Map<String, dynamic> toJson() => {"calories": calories, "protein": protein, "carbs": carbs, "fats": fats};
}

/// One suggested meal (breakfast/lunch/dinner/snack/smoothie) — mirrors the
/// program-entry shape NutritionBuilder.jsx's `addToProgram` writes: a copy
/// of the catalog MealDef plus scaling-to-budget fields (targetCalories/
/// scale/scaledIngredients/scaledMacros, all set once at add-time — they
/// don't recompute automatically if the budget changes later) and coach
/// per-ingredient qty overrides on top of that.
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
    this.instructions,
    this.notes,
    this.isCustom = false,
    this.targetCalories,
    this.scale,
    this.scaledIngredients,
    this.scaledMacros,
    this.overrides = const {},
  });

  final String id;
  final String name;
  final String? time;
  final int calories;
  final double protein;
  final double carbs;
  final double fats;
  final List<Ingredient> ingredients;
  final String? instructions;
  final String? notes;
  final bool isCustom;

  /// The Calorie Budget box's value for this meal's category at the moment
  /// it was added — null if no budget was set then.
  final int? targetCalories;
  final double? scale;
  final List<Ingredient>? scaledIngredients;
  final MacroSnapshot? scaledMacros;

  /// Ingredient-list index -> coach-typed replacement qty (raw string, kept
  /// as typed rather than parsed so "" mid-edit doesn't snap back).
  final Map<int, String> overrides;

  NutritionMeal copyWith({
    String? time,
    Map<int, String>? overrides,
    bool clearOverrides = false,
  }) =>
      NutritionMeal(
        id: id,
        name: name,
        time: time ?? this.time,
        calories: calories,
        protein: protein,
        carbs: carbs,
        fats: fats,
        ingredients: ingredients,
        instructions: instructions,
        notes: notes,
        isCustom: isCustom,
        targetCalories: targetCalories,
        scale: scale,
        scaledIngredients: scaledIngredients,
        scaledMacros: scaledMacros,
        overrides: clearOverrides ? const {} : (overrides ?? this.overrides),
      );
}

/// A coach-uploaded PDF attached to a client's nutrition plan (guidelines,
/// meal plan handout, etc.) — mirrors NutritionBuilder.jsx's
/// `nutrition.attachments`. Stored as a base64 data URL, same convention
/// as profile photos (no real object storage yet), capped at 2MB.
class NutritionAttachment {
  const NutritionAttachment({required this.id, required this.name, required this.dataUrl, required this.size});

  final String id;
  final String name;
  final String dataUrl;
  final int size;
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
    this.attachments = const [],
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
  final List<NutritionAttachment> attachments;

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
    List<NutritionAttachment>? attachments,
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
        attachments: attachments ?? this.attachments,
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
