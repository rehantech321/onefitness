import "package:flutter/material.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/nutrition_helpers.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/nutrition_plan.dart";

/// Lets a client change how much of each ingredient is in one of their
/// meals, with the calories and macros updating as they type.
///
/// Nothing is recalculated by hand here: every catalogue ingredient carries
/// its macros per one unit, so [effectiveMacros] already derives a meal's
/// totals from its quantities — the same function the coach-side builder
/// uses. This screen only edits the quantities and shows the result, which
/// is why a meal always adds up the same way whoever changed it.
///
/// Edits are stored as per-ingredient overrides rather than by rewriting
/// the meal, so the original recipe is never lost and "Reset" can put it
/// back exactly.
Future<NutritionMeal?> showMealIngredientEditor(
  BuildContext context, {
  required NutritionMeal meal,
  int? budget,
}) {
  return showModalBottomSheet<NutritionMeal>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _MealEditorSheet(meal: meal, budget: budget),
  );
}

class _MealEditorSheet extends StatefulWidget {
  const _MealEditorSheet({required this.meal, this.budget});
  final NutritionMeal meal;
  final int? budget;

  @override
  State<_MealEditorSheet> createState() => _MealEditorSheetState();
}

class _MealEditorSheetState extends State<_MealEditorSheet> {
  /// Working copy of the quantity overrides, keyed by ingredient index —
  /// the shape NutritionMeal already stores and effectiveMacros reads.
  late Map<int, String> _overrides = {...widget.meal.overrides};

  late final List<TextEditingController> _controllers = [
    for (final ing in effectiveIngredients(widget.meal))
      TextEditingController(text: fmtQty(ing.qty)),
  ];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  NutritionMeal get _working => widget.meal.copyWith(overrides: _overrides);

  /// Base ingredients, so an override can be removed when the client types
  /// the original amount back in.
  List<Ingredient> get _base => widget.meal.scaledIngredients ?? widget.meal.ingredients;

  void _setQty(int i, String raw) {
    final text = raw.trim();
    final parsed = num.tryParse(text);
    setState(() {
      if (text.isEmpty || parsed == null) {
        // Mid-typing ("1.", "") — leave the last good value in place rather
        // than flashing the macros to zero.
        return;
      }
      if (i < _base.length && _base[i].qty == parsed) {
        _overrides.remove(i);
      } else {
        _overrides[i] = text;
      }
    });
  }

  void _reset() {
    setState(() {
      _overrides = {};
      final base = effectiveIngredients(widget.meal.copyWith(clearOverrides: true));
      for (var i = 0; i < _controllers.length && i < base.length; i++) {
        _controllers[i].text = fmtQty(base[i].qty);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ings = effectiveIngredients(_working);
    final macros = effectiveMacros(_working);
    final budget = widget.budget;
    final overBudget = budget != null && budget > 0 && macros.calories > budget * 1.1;
    final canRecalculate = computeMacrosFromIngredients(ings) != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(widget.meal.name,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 20, color: AppColors.mute),
                      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),

              // The live total, pinned above the list so the effect of a
              // change is visible without scrolling back up.
              Container(
                margin: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  border: Border.all(color: overBudget ? const Color(0xFFA8632F) : AppColors.goldDim),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("${macros.calories} kcal",
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.gold)),
                        if (budget != null && budget > 0)
                          Text("Budget $budget",
                              style: const TextStyle(fontSize: 11.5, color: AppColors.mute)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Protein ${macros.protein}g · Carbs ${macros.carbs}g · Fat ${macros.fats}g",
                      style: const TextStyle(fontSize: 12.5, color: AppColors.mute),
                    ),
                    if (!canRecalculate)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          "This meal's ingredients don't carry nutrition data, so the "
                          "totals are adjusted proportionally rather than recalculated.",
                          style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
                        ),
                      ),
                    if (overBudget)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          "Over this meal's calorie budget — that's fine if it fits your day.",
                          style: TextStyle(fontSize: 11, color: Color(0xFFD68A4F), height: 1.4),
                        ),
                      ),
                  ],
                ),
              ),

              const Padding(
                padding: EdgeInsets.fromLTRB(18, 14, 18, 6),
                child: Text("INGREDIENTS",
                    style: TextStyle(
                        fontSize: 11, color: AppColors.mute, fontWeight: FontWeight.w700, letterSpacing: 1)),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                  itemCount: ings.length,
                  itemBuilder: (ctx, i) {
                    final ing = ings[i];
                    final changed = _overrides.containsKey(i);
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: AppColors.line)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(ing.item, style: const TextStyle(fontSize: 13.5)),
                                if (changed)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 1),
                                    child: Text("changed",
                                        style: TextStyle(
                                            fontSize: 10, color: AppColors.gold, fontWeight: FontWeight.w700)),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 74,
                            child: AppField(
                              controller: _controllers[i],
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (v) => _setQty(i, v),
                            ),
                          ),
                          if (ing.unit != null) ...[
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 44,
                              child: Text(ing.unit!,
                                  style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                child: Row(
                  children: [
                    if (_overrides.isNotEmpty) ...[
                      Expanded(
                        child: BtnGhost(
                          onPressed: _reset,
                          child: const Text("Reset"),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      flex: 2,
                      child: BtnGold(
                        full: true,
                        onPressed: () => Navigator.of(context).pop(_working),
                        child: const Text("Save changes"),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
