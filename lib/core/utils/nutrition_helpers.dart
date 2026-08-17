import "../../data/models/ingredient_grocery_item.dart";
import "../../data/models/meal_def.dart";
import "../../data/models/nutrition_plan.dart";

/// Mirrors nutritionHelpers.js `fmtQty` — whole numbers print bare, else
/// rounded to 2 decimal places.
String fmtQty(num? qty) {
  if (qty == null) return "";
  if (qty % 1 == 0) return qty.toInt().toString();
  final rounded = (qty * 100).round() / 100;
  return rounded % 1 == 0 ? rounded.toInt().toString() : rounded.toString();
}

/// Mirrors nutritionHelpers.js `scaleMeal` — linear scaling of a catalog
/// meal's ingredients/macros to a target calorie count; preserves macro
/// ratios. Null when there's no target or the meal has no base calories.
class ScaledMeal {
  const ScaledMeal({required this.scale, required this.scaledIngredients, required this.scaledMacros});
  final double scale;
  final List<Ingredient> scaledIngredients;
  final MacroSnapshot scaledMacros;
}

ScaledMeal? scaleMeal(MealDef meal, int? targetCalories) {
  if (targetCalories == null || targetCalories <= 0 || meal.calories <= 0) return null;
  final scale = targetCalories / meal.calories;
  final scaledIngredients = meal.ingredients
      .map((ing) => ing.qty != null ? ing.copyWith(qty: (ing.qty! * scale * 10).round() / 10) : ing)
      .toList();
  return ScaledMeal(
    scale: scale,
    scaledIngredients: scaledIngredients,
    scaledMacros: MacroSnapshot(
      calories: targetCalories,
      protein: (meal.protein * scale * 10).round() / 10,
      carbs: (meal.carbs * scale * 10).round() / 10,
      fats: (meal.fats * scale * 10).round() / 10,
    ),
  );
}

/// Mirrors nutritionHelpers.js `effectiveIngredients` — scaled ingredients
/// (falling back to the base catalog list) with any coach qty overrides
/// applied on top.
List<Ingredient> effectiveIngredients(NutritionMeal meal) {
  final base = meal.scaledIngredients ?? meal.ingredients;
  return [
    for (var i = 0; i < base.length; i++)
      meal.overrides.containsKey(i) ? base[i].copyWith(qty: num.tryParse(meal.overrides[i] ?? "")) : base[i],
  ];
}

/// Mirrors nutritionHelpers.js `computeMacrosFromIngredients` — sums
/// per-ingredient macro density × qty; null if none of the ingredients
/// carry macro data (e.g. a legacy/manually-entered meal).
MacroSnapshot? computeMacrosFromIngredients(List<Ingredient> ings) {
  double calories = 0, protein = 0, carbs = 0, fats = 0;
  var hasMacroData = false;
  for (final ing in ings) {
    final m = ing.macros;
    if (m == null) continue;
    hasMacroData = true;
    final qty = ing.qty?.toDouble();
    if (qty == null) continue;
    calories += m.cals * qty;
    protein += m.p * qty;
    carbs += m.c * qty;
    fats += m.f * qty;
  }
  if (!hasMacroData) return null;
  return MacroSnapshot(
    calories: calories.round(),
    protein: (protein * 10).round() / 10,
    carbs: (carbs * 10).round() / 10,
    fats: (fats * 10).round() / 10,
  );
}

/// Mirrors nutritionHelpers.js `effectiveMacros` — the macro totals actually
/// shown for a program meal: live per-ingredient recompute when possible,
/// else the scaled totals proportionally adjusted for any qty overrides,
/// else the meal's own base totals.
MacroSnapshot effectiveMacros(NutritionMeal meal) {
  final scaledMacros = meal.scaledMacros;
  final base = meal.scaledIngredients ?? meal.ingredients;
  final ings = [
    for (var i = 0; i < base.length; i++)
      meal.overrides.containsKey(i) ? base[i].copyWith(qty: num.tryParse(meal.overrides[i] ?? "")) : base[i],
  ];
  final computed = computeMacrosFromIngredients(ings);
  if (computed != null) return computed;
  if (scaledMacros == null) {
    return MacroSnapshot(calories: meal.calories, protein: meal.protein, carbs: meal.carbs, fats: meal.fats);
  }
  if (meal.overrides.isEmpty || base.isEmpty) return scaledMacros;
  double sumBase = 0, sumEff = 0;
  var any = false;
  for (var i = 0; i < base.length; i++) {
    final baseQty = base[i].qty?.toDouble();
    final effQty = meal.overrides.containsKey(i) ? double.tryParse(meal.overrides[i] ?? "") : baseQty;
    if (baseQty != null && effQty != null) {
      sumBase += baseQty;
      sumEff += effQty;
      any = true;
    }
  }
  if (!any || sumBase == 0) return scaledMacros;
  final ratio = sumEff / sumBase;
  return MacroSnapshot(
    calories: (scaledMacros.calories * ratio).round(),
    protein: (scaledMacros.protein * ratio * 10).round() / 10,
    carbs: (scaledMacros.carbs * ratio * 10).round() / 10,
    fats: (scaledMacros.fats * ratio * 10).round() / 10,
  );
}

/// "How close is this meal to its calorie target" — mirrors
/// nutritionHelpers.js `targetMatchInfo`.
class TargetMatch {
  const TargetMatch({required this.delta, required this.pct, required this.colorHex});
  final int delta;
  final int pct;
  final int colorHex; // 0xRRGGBB
}

TargetMatch? targetMatchInfo(num actual, int? target) {
  if (target == null || target == 0) return null;
  final delta = (actual - target).round();
  final pct = (actual / target * 100).round();
  final colorHex = delta.abs() <= 30 ? 0x4EC97A : (delta.abs() <= 80 ? 0xD68A4F : 0xC97F7F);
  return TargetMatch(delta: delta, pct: pct, colorHex: colorHex);
}

/// Mirrors nutritionHelpers.js `buildGroceryList` — every meal's effective
/// ingredients, categorized and deduplicated (summed) by item+unit.
class GroceryCategory {
  const GroceryCategory({required this.key, required this.label, required this.items});
  final String key;
  final String label;
  final List<IngredientGroceryItem> items;
}

List<GroceryCategory> buildGroceryList(NutritionPlan plan) {
  final allEntries = [...plan.breakfast, ...plan.lunch, ...plan.dinner, ...plan.snacks, ...plan.smoothies];
  final buckets = <String, Map<String, IngredientGroceryItem>>{
    for (final c in kIngredientCategories) c.$1: {},
  };

  for (final meal in allEntries) {
    for (final ing in effectiveIngredients(meal)) {
      final cat = kIngredientCategories.any((c) => c.$1 == ing.category) ? ing.category! : "pantry";
      final key = "${ing.item.trim().toLowerCase()}|${(ing.unit ?? "").trim().toLowerCase()}";
      final bucket = buckets[cat]!;
      final existing = bucket[key];
      if (existing != null && existing.qty != null && ing.qty != null) {
        bucket[key] = IngredientGroceryItem(item: existing.item, qty: existing.qty! + ing.qty!, unit: existing.unit);
      } else if (!bucket.containsKey(key)) {
        bucket[key] = IngredientGroceryItem(item: ing.item, qty: ing.qty, unit: ing.unit);
      }
    }
  }

  return kIngredientCategories
      .map((c) => GroceryCategory(key: c.$1, label: c.$2, items: buckets[c.$1]!.values.toList()..sort((a, b) => a.item.compareTo(b.item))))
      .where((c) => c.items.isNotEmpty)
      .toList();
}

/// Mirrors nutritionHelpers.js `groceryListAsText` — plain-text export for
/// the "Copy list" button.
String groceryListAsText(List<GroceryCategory> categories, String? extra) {
  var out = categories
      .map((cat) => "${cat.label}:\n${cat.items.map((it) => "- ${it.item}${it.qty != null ? " (${fmtQty(it.qty)}${it.unit != null && it.unit!.isNotEmpty ? " ${it.unit}" : ""})" : ""}").join("\n")}")
      .join("\n\n");
  if (extra != null && extra.trim().isNotEmpty) out += "\n\nAdditional Items:\n${extra.trim()}";
  return out;
}
