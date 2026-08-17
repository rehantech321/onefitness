import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/nutrition_helpers.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/nutrition_plan.dart";

/// Mirrors ScaledMealCard.jsx — one meal inside a program category: macro
/// pills, a target-match bar against the category's calorie budget,
/// per-ingredient qty override inputs (falls back to the auto-scaled qty),
/// collapsible instructions, notes, and a time-slot field.
class ScaledMealCard extends StatefulWidget {
  const ScaledMealCard({super.key, required this.meal, required this.onUpdate, required this.onRemove});

  final NutritionMeal meal;
  final ValueChanged<NutritionMeal> onUpdate;
  final VoidCallback onRemove;

  @override
  State<ScaledMealCard> createState() => _ScaledMealCardState();
}

class _ScaledMealCardState extends State<ScaledMealCard> {
  bool _showInstructions = false;

  @override
  Widget build(BuildContext context) {
    final meal = widget.meal;
    final macros = effectiveMacros(meal);
    final ings = effectiveIngredients(meal);
    final match = meal.targetCalories != null ? targetMatchInfo(macros.calories, meal.targetCalories) : null;
    final hasOverrides = meal.overrides.isNotEmpty;
    final matchColor = match != null ? Color(0xFF000000 | match.colorHex) : null;

    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Text(meal.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    if (meal.isCustom) const Tag(text: "Custom", gold: true),
                    if (hasOverrides) const Tag(text: "Adjusted"),
                  ],
                ),
              ),
              IconButton(onPressed: widget.onRemove, icon: const Icon(LucideIcons.trash2, size: 15, color: Color(0xFF6B3B3B))),
            ],
          ),
          if (macros.calories > 0 || macros.protein > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 10,
                runSpacing: 6,
                children: [
                  _MacroPill(label: "CAL", value: "${macros.calories}"),
                  _MacroPill(label: "PG", value: fmtQty(macros.protein)),
                  _MacroPill(label: "CG", value: fmtQty(macros.carbs)),
                  _MacroPill(label: "FG", value: fmtQty(macros.fats)),
                ],
              ),
            ),
          if (match != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Target: ${meal.targetCalories} kcal", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                      Text(
                        match.delta == 0 ? "On target ✓" : "${match.delta > 0 ? "+" : ""}${match.delta} kcal (${match.pct}%)",
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: matchColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: (match.pct.clamp(0, 130)) / 130,
                      minHeight: 4,
                      backgroundColor: AppColors.line,
                      valueColor: AlwaysStoppedAnimation(matchColor),
                    ),
                  ),
                  if (hasOverrides)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text("⚠ Macros are estimates after manual adjustments.", style: TextStyle(fontSize: 10, color: AppColors.mute)),
                    ),
                ],
              ),
            ),
          ],
          if (ings.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.only(top: 10),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "INGREDIENTS${meal.scaledIngredients != null ? " (SCALED)" : ""}",
                    style: const TextStyle(fontSize: 10, color: AppColors.gold, fontWeight: FontWeight.w700, letterSpacing: 0.8),
                  ),
                  const SizedBox(height: 8),
                  ...ings.asMap().entries.map((entry) {
                    final i = entry.key;
                    final ing = entry.value;
                    final isOverridden = meal.overrides.containsKey(i);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(flex: 3, child: Text(ing.item, style: const TextStyle(fontSize: 12, color: AppColors.txt))),
                          SizedBox(
                            width: 64,
                            child: TextField(
                              controller: TextEditingController(text: meal.overrides[i] ?? (ing.qty != null ? fmtQty(ing.qty) : "")),
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 12, color: AppColors.txt),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
                                filled: true,
                                fillColor: isOverridden ? const Color(0x1433733F) : AppColors.bg,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: isOverridden ? AppColors.goldDim : AppColors.line)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: isOverridden ? AppColors.goldDim : AppColors.line)),
                              ),
                              onChanged: (v) {
                                final next = Map<int, String>.from(meal.overrides);
                                if (v.isEmpty) {
                                  next.remove(i);
                                } else {
                                  next[i] = v;
                                }
                                widget.onUpdate(meal.copyWith(overrides: next));
                              },
                            ),
                          ),
                          SizedBox(width: 32, child: Padding(padding: const EdgeInsets.only(left: 8), child: Text(ing.unit ?? "", style: const TextStyle(fontSize: 11, color: AppColors.mute)))),
                        ],
                      ),
                    );
                  }),
                  if (hasOverrides)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: GestureDetector(
                        onTap: () => widget.onUpdate(meal.copyWith(clearOverrides: true)),
                        child: const Text("Reset all to auto-scaled", style: TextStyle(fontSize: 11, color: AppColors.mute, decoration: TextDecoration.underline)),
                      ),
                    ),
                ],
              ),
            ),
          if (meal.instructions != null && meal.instructions!.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: GestureDetector(
                onTap: () => setState(() => _showInstructions = !_showInstructions),
                child: Text(
                  _showInstructions ? "Hide instructions ▲" : "Show instructions ▼",
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gold),
                ),
              ),
            ),
            if (_showInstructions)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(meal.instructions!, style: const TextStyle(fontSize: 12, color: AppColors.txt, height: 1.5)),
              ),
          ],
          if (meal.notes != null && meal.notes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(meal.notes!, style: const TextStyle(fontSize: 12, color: AppColors.mute, fontStyle: FontStyle.italic)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: AppField(
              controller: TextEditingController(text: meal.time ?? ""),
              placeholder: "When? (optional, e.g. 7am)",
              onChanged: (v) => widget.onUpdate(meal.copyWith(time: v)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MacroPill extends StatelessWidget {
  const _MacroPill({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(7)),
      constraints: const BoxConstraints(minWidth: 44),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.gold)),
          Text(label, style: const TextStyle(fontSize: 9, color: AppColors.mute, letterSpacing: 0.3)),
        ],
      ),
    );
  }
}
