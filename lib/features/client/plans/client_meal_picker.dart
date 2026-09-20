import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/meal_def.dart";
import "../../../data/models/nutrition_plan.dart";
import "../../../data/providers/trainer_providers.dart";

/// Lets a client pick their own meal for breakfast / lunch / dinner once
/// their program has calorie targets and per-meal budgets. Meals come from
/// the same catalogue coaches build programs from, so what a client picks
/// carries real ingredients and macros into their grocery list.
///
/// [budget] is that meal's calorie budget: meals within 15% of it are marked
/// "fits your budget" and listed first, but nothing is hidden — the budget
/// is guidance, not a lock.
Future<NutritionMeal?> showClientMealPicker(
  BuildContext context,
  WidgetRef ref, {
  required String category,
  required String label,
  int? budget,
}) {
  return showModalBottomSheet<NutritionMeal>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _ClientMealPickerBody(category: category, label: label, budget: budget),
    ),
  );
}

class _ClientMealPickerBody extends ConsumerStatefulWidget {
  const _ClientMealPickerBody({required this.category, required this.label, this.budget});
  final String category;
  final String label;
  final int? budget;

  @override
  ConsumerState<_ClientMealPickerBody> createState() => _ClientMealPickerBodyState();
}

class _ClientMealPickerBodyState extends ConsumerState<_ClientMealPickerBody> {
  final _search = TextEditingController();
  bool _budgetOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _fitsBudget(MealDef m) {
    final b = widget.budget;
    if (b == null || b <= 0 || m.calories <= 0) return false;
    return (m.calories - b).abs() <= b * 0.15;
  }

  NutritionMeal _toMeal(MealDef m) => NutritionMeal(
        id: m.id,
        name: m.name,
        calories: m.calories,
        protein: m.protein,
        carbs: m.carbs,
        fats: m.fats,
        ingredients: m.ingredients,
        instructions: m.instructions,
        notes: m.notes,
        isCustom: m.isCustom,
        targetCalories: widget.budget,
      );

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final all = [...ref.watch(mealCatalogProvider), ...ref.watch(customMealsProvider)]
        .where((m) => m.mealType == widget.category)
        .where((m) => q.isEmpty || m.name.toLowerCase().contains(q) || m.ingredients.any((i) => i.item.toLowerCase().contains(q)))
        .where((m) => !_budgetOnly || _fitsBudget(m))
        .toList()
      // Closest to the budget first when there is one.
      ..sort((a, b) {
        if (widget.budget == null) return a.name.compareTo(b.name);
        return (a.calories - widget.budget!).abs().compareTo((b.calories - widget.budget!).abs());
      });

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel("Choose your ${widget.label.toLowerCase()}"),
            if (widget.budget != null)
              Text(
                "Your program allows about ${widget.budget} kcal for ${widget.label.toLowerCase()}.",
                style: const TextStyle(fontSize: 12, color: AppColors.mute),
              ),
            const SizedBox(height: 10),
            AppField(
              controller: _search,
              placeholder: "Search meals or ingredients…",
              onChanged: (_) => setState(() {}),
            ),
            if (widget.budget != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Switch(
                    value: _budgetOnly,
                    onChanged: (v) => setState(() => _budgetOnly = v),
                    activeThumbColor: AppColors.gold,
                  ),
                  const Text("Only show meals that fit my budget", style: TextStyle(fontSize: 12, color: AppColors.mute)),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Flexible(
              child: all.isEmpty
                  ? const HintBox(text: "No meals match. Try a different search, or switch off the budget filter.")
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: all.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final m = all[i];
                        final fits = _fitsBudget(m);
                        return AppCard(
                          margin: EdgeInsets.zero,
                          borderColor: fits ? AppColors.gold : null,
                          onTap: () => Navigator.of(context).pop(_toMeal(m)),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(m.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 2),
                                    Text(
                                      "${m.calories} kcal · P ${m.protein.toInt()} · C ${m.carbs.toInt()} · F ${m.fats.toInt()}",
                                      style: const TextStyle(fontSize: 11.5, color: AppColors.mute),
                                    ),
                                    if (fits)
                                      const Padding(
                                        padding: EdgeInsets.only(top: 2),
                                        child: Text("Fits your budget", style: TextStyle(fontSize: 11, color: AppColors.gold, fontWeight: FontWeight.w700)),
                                      ),
                                  ],
                                ),
                              ),
                              const Icon(LucideIcons.chevronRight, size: 16, color: AppColors.mute),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
