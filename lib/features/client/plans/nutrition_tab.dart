import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/nutrition_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/nutrition_plan.dart";
import "../../../data/providers/client_providers.dart";

/// Mirrors NutritionScreenReadOnly.jsx: training/rest macro targets, a
/// reference-only calorie budget panel, suggested meals per category, a
/// consolidated grocery list, and coach guidelines.
class NutritionTab extends ConsumerStatefulWidget {
  const NutritionTab({super.key});

  @override
  ConsumerState<NutritionTab> createState() => _NutritionTabState();
}

class _NutritionTabState extends ConsumerState<NutritionTab> {
  String _dayType = "training";
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(clientRecordProvider);
    final n = client.nutrition;

    if (n == null) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: HintBox(text: "Complete your Nutritional Assessment (under Forms) so your coach can build your nutrition program. It'll show up here."),
      );
    }

    final targets = _dayType == "training" ? n.trainingTargets.asMap() : n.restTargets.asMap();
    final hasTargets = targets.values.any((v) => v != null && v.isNotEmpty);
    final dailyCal = int.tryParse(targets["calories"] ?? "") ?? 0;

    final allMeals = [...n.breakfast, ...n.lunch, ...n.dinner, ...n.snacks, ...n.smoothies];
    final grocery = buildGroceryList(allMeals);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasTargets) ...[
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.card,
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _DayTypeButton(label: "Training Day", selected: _dayType == "training", onTap: () => setState(() => _dayType = "training")),
                  _DayTypeButton(label: "Rest Day", selected: _dayType == "rest", onTap: () => setState(() => _dayType = "rest")),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SectionLabel("${_dayType == 'training' ? 'Training' : 'Rest'} Day Targets"),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kMacroFields.where((f) => targets[f.$1] != null && targets[f.$1]!.isNotEmpty).map((f) {
                final (key, _, unit) = f;
                return Container(
                  width: (MediaQuery.of(context).size.width - 18 * 2 - 8 * 2) / 3,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Text(
                        "${targets[key]}${unit == '%' ? '%' : ''}",
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.gold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        macroShortLabel(key).toUpperCase(),
                        style: const TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
            _CalorieBudgetPanel(mealBudgets: _dayType == "training" ? n.mealBudgets.training : n.mealBudgets.rest, dailyCalTarget: dailyCal),
            const SizedBox(height: 18),
          ],

          _MealSection(title: "Breakfast", meals: n.breakfast),
          _MealSection(title: "Lunch", meals: n.lunch),
          _MealSection(title: "Dinner", meals: n.dinner),
          if (n.snacks.isNotEmpty || n.smoothies.isNotEmpty)
            _MealSection(title: "Snacks and/or Smoothies", meals: [...n.snacks, ...n.smoothies]),

          if (grocery.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SectionLabel("Grocery List"),
                OutlinedButton(
                  onPressed: () {
                    final text = grocery
                        .map((it) => "- ${it.item}${it.qty != null ? " (${fmtQty(it.qty)}${it.unit != null ? ' ${it.unit}' : ''})" : ""}")
                        .join("\n");
                    Clipboard.setData(ClipboardData(text: text));
                    setState(() => _copied = true);
                    Future.delayed(const Duration(milliseconds: 1500), () {
                      if (mounted) setState(() => _copied = false);
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.gold,
                    side: const BorderSide(color: AppColors.line),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(_copied ? "Copied!" : "Copy", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: grocery
                    .map((it) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(it.item, style: const TextStyle(fontSize: 13, color: AppColors.txt)),
                              Text(
                                "${fmtQty(it.qty)}${it.unit != null ? ' ${it.unit}' : ''}",
                                style: const TextStyle(fontSize: 13, color: AppColors.mute),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],

          if (n.guidelines != null && n.guidelines!.isNotEmpty) ...[
            const SectionLabel("Guidelines"),
            AppCard(
              child: Text(n.guidelines!, style: const TextStyle(fontSize: 13, color: AppColors.txt, height: 1.6)),
            ),
          ],
        ],
      ),
    );
  }
}

class _DayTypeButton extends StatelessWidget {
  const _DayTypeButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.gold : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? Colors.white : AppColors.mute),
          ),
        ),
      ),
    );
  }
}

class _CalorieBudgetPanel extends StatelessWidget {
  const _CalorieBudgetPanel({required this.mealBudgets, required this.dailyCalTarget});
  final Map<String, String> mealBudgets;
  final int dailyCalTarget;

  @override
  Widget build(BuildContext context) {
    final allocated = ["breakfast", "lunch", "dinner", "snacks", "smoothies"]
        .fold<int>(0, (s, k) => s + (int.tryParse(mealBudgets[k] ?? "") ?? 0));
    final remaining = dailyCalTarget - allocated;
    final over = remaining < 0;
    final allGood = dailyCalTarget > 0 && !over && remaining.abs() < 10;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "CALORIE BUDGET · REFERENCE ONLY",
            style: TextStyle(fontSize: 10, color: AppColors.gold, fontWeight: FontWeight.w700, letterSpacing: 1),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _BudgetBox(label: "Breakfast", value: mealBudgets["breakfast"]),
              _BudgetBox(label: "Lunch", value: mealBudgets["lunch"]),
              _BudgetBox(label: "Dinner", value: mealBudgets["dinner"]),
              _BudgetBox(label: "Snacks & Smoothies", value: mealBudgets["snacks"]),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 11, color: AppColors.mute),
                  children: [
                    const TextSpan(text: "Total: "),
                    TextSpan(text: "$allocated kcal", style: const TextStyle(color: AppColors.txt, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              if (dailyCalTarget > 0)
                Text(
                  allGood ? "✓ On target" : (over ? "${remaining.abs()} kcal over" : "$remaining kcal left"),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: allGood ? AppColors.grn : (over ? AppColors.errorText : AppColors.gold),
                  ),
                ),
            ],
          ),
          if (dailyCalTarget > 0) ...[
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: (allocated / dailyCalTarget).clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor: AppColors.line,
                valueColor: AlwaysStoppedAnimation(over ? AppColors.errorText : AppColors.gold),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            "Daily target: ${dailyCalTarget > 0 ? '$dailyCalTarget kcal' : 'not set'}",
            style: const TextStyle(fontSize: 9, color: AppColors.mute),
          ),
        ],
      ),
    );
  }
}

class _BudgetBox extends StatelessWidget {
  const _BudgetBox({required this.label, this.value});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 8.5, color: AppColors.mute, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 3),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.bg,
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                value ?? "—",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: value != null ? AppColors.gold : AppColors.mute),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MealSection extends StatelessWidget {
  const _MealSection({required this.title, required this.meals});
  final String title;
  final List<NutritionMeal> meals;

  @override
  Widget build(BuildContext context) {
    if (meals.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(title),
          ...meals.map((meal) => AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(meal.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                        if (meal.time != null) Text(meal.time!, style: const TextStyle(fontSize: 12, color: AppColors.gold)),
                      ],
                    ),
                    if (meal.calories > 0 || meal.protein > 0) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _MacroChip(label: "Cal", value: "${meal.calories}"),
                          _MacroChip(label: "Pg", value: "${meal.protein.toInt()}"),
                          _MacroChip(label: "Cg", value: "${meal.carbs.toInt()}"),
                          _MacroChip(label: "Fg", value: "${meal.fats.toInt()}"),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                    ...meal.ingredients.map((ing) => Container(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: AppColors.line)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(ing.item, style: const TextStyle(fontSize: 13, color: AppColors.txt)),
                              Text(
                                "${fmtQty(ing.qty)}${ing.unit != null ? ' ${ing.unit}' : ''}",
                                style: const TextStyle(fontSize: 13, color: AppColors.mute),
                              ),
                            ],
                          ),
                        )),
                    if (meal.notes != null && meal.notes!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(meal.notes!, style: const TextStyle(fontSize: 12, color: AppColors.mute, fontStyle: FontStyle.italic)),
                      ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _MacroChip extends StatelessWidget {
  const _MacroChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 44),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(7)),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.gold)),
          Text(label, style: const TextStyle(fontSize: 9, color: AppColors.mute, letterSpacing: 0.3)),
        ],
      ),
    );
  }
}
