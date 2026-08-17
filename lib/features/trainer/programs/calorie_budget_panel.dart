import "package:flutter/material.dart";
import "../../../core/theme/app_colors.dart";

/// Mirrors CalorieBudgetPanel.jsx — 4 compact per-meal calorie boxes
/// (Breakfast/Lunch/Dinner/"Snacks & Smoothies" — the last box's key is
/// "snacks" only, matching the web; smoothies budget has no box of its own
/// but still counts toward the allocated total), a running total vs. the
/// day's target, and a progress bar.
class CalorieBudgetPanel extends StatelessWidget {
  const CalorieBudgetPanel({super.key, required this.mealBudgets, required this.onChange, required this.dailyCalTarget});

  final Map<String, String> mealBudgets;
  final ValueChanged<Map<String, String>> onChange;
  final int dailyCalTarget;

  static const _boxes = [("breakfast", "Breakfast"), ("lunch", "Lunch"), ("dinner", "Dinner"), ("snacks", "Snacks & Smoothies")];

  @override
  Widget build(BuildContext context) {
    final allocated = ["breakfast", "lunch", "dinner", "snacks", "smoothies"]
        .fold<double>(0, (sum, k) => sum + (double.tryParse(mealBudgets[k] ?? "") ?? 0));
    final remaining = dailyCalTarget - allocated;
    final over = remaining < 0;
    final allGood = dailyCalTarget > 0 && !over && remaining.abs() < 10;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("CALORIE BUDGET", style: TextStyle(fontSize: 10, color: AppColors.gold, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 7),
          Row(
            children: _boxes
                .map((b) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2.5),
                        child: Column(
                          children: [
                            Text(b.$2.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 7.5, color: AppColors.mute, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 3),
                            TextField(
                              controller: TextEditingController(text: mealBudgets[b.$1] ?? "")..selection = TextSelection.collapsed(offset: (mealBudgets[b.$1] ?? "").length),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.txt, fontSize: 12),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                hintText: "kcal",
                                hintStyle: const TextStyle(color: AppColors.mute, fontSize: 11),
                                filled: true,
                                fillColor: AppColors.bg,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.line)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.line)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.gold)),
                              ),
                              onChanged: (v) => onChange({...mealBudgets, b.$1: v}),
                            ),
                          ],
                        ),
                      ),
                    ))
                .toList(),
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
                    TextSpan(text: "${allocated.round()} kcal", style: const TextStyle(color: AppColors.txt, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              if (dailyCalTarget > 0)
                Text(
                  allGood ? "✓ On target" : (over ? "${remaining.abs().round()} kcal over" : "${remaining.round()} kcal left"),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: allGood ? AppColors.grn : (over ? const Color(0xFFC97F7F) : AppColors.gold)),
                ),
            ],
          ),
          if (dailyCalTarget > 0) ...[
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: (allocated / dailyCalTarget).clamp(0, 1).toDouble(),
                minHeight: 3,
                backgroundColor: AppColors.line,
                valueColor: AlwaysStoppedAnimation(over ? const Color(0xFFC97F7F) : AppColors.gold),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            "Daily target: ${dailyCalTarget > 0 ? "$dailyCalTarget kcal" : "not set"} · Edit ingredients below to adjust meal totals",
            style: const TextStyle(fontSize: 9, color: AppColors.mute),
          ),
        ],
      ),
    );
  }
}
