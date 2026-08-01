import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/nutrition_library_entry.dart";
import "../../../data/models/nutrition_plan.dart";
import "../../../data/providers/trainer_providers.dart";
import "meal_picker_sheet.dart";

const _mealCategories = [("breakfast", "Breakfast"), ("lunch", "Lunch"), ("dinner", "Dinner"), ("snacks", "Snacks"), ("smoothies", "Smoothies")];

/// Mirrors NutritionBuilder.jsx — training/rest day macro targets, a
/// per-category meal-budget panel, and the 5 meal-category editors. When
/// [clientId] is set, saving writes directly to that client's
/// ClientRecord.nutrition; otherwise (drawer "Build Nutrition Program") it
/// saves into the shared template library.
class NutritionBuilderScreen extends ConsumerStatefulWidget {
  const NutritionBuilderScreen({super.key, this.clientId, this.existing});

  final String? clientId;
  final NutritionPlan? existing;

  @override
  ConsumerState<NutritionBuilderScreen> createState() => _NutritionBuilderScreenState();
}

class _NutritionBuilderScreenState extends ConsumerState<NutritionBuilderScreen> {
  late MacroTargets _training = widget.existing?.trainingTargets ?? const MacroTargets();
  late MacroTargets _rest = widget.existing?.restTargets ?? const MacroTargets();
  late Map<String, String> _budgets = {...(widget.existing?.mealBudgets ?? {})};
  late List<NutritionMeal> _breakfast = [...(widget.existing?.breakfast ?? [])];
  late List<NutritionMeal> _lunch = [...(widget.existing?.lunch ?? [])];
  late List<NutritionMeal> _dinner = [...(widget.existing?.dinner ?? [])];
  late List<NutritionMeal> _snacks = [...(widget.existing?.snacks ?? [])];
  late List<NutritionMeal> _smoothies = [...(widget.existing?.smoothies ?? [])];
  late final _guidelines = TextEditingController(text: widget.existing?.guidelines ?? "");

  List<NutritionMeal> _listFor(String cat) => switch (cat) {
        "breakfast" => _breakfast,
        "lunch" => _lunch,
        "dinner" => _dinner,
        "snacks" => _snacks,
        _ => _smoothies,
      };

  void _setListFor(String cat, List<NutritionMeal> list) => setState(() {
        switch (cat) {
          case "breakfast":
            _breakfast = list;
          case "lunch":
            _lunch = list;
          case "dinner":
            _dinner = list;
          case "snacks":
            _snacks = list;
          default:
            _smoothies = list;
        }
      });

  Future<void> _addMeal(String cat) async {
    final picked = await showMealPickerSheet(context, cat);
    if (picked == null) return;
    _setListFor(cat, [
      ..._listFor(cat),
      NutritionMeal(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: picked.name,
        calories: picked.calories,
        protein: picked.protein,
        carbs: picked.carbs,
        fats: picked.fats,
        ingredients: picked.ingredients.map((i) => Ingredient(item: i)).toList(),
        notes: picked.instructions,
      ),
    ]);
  }

  NutritionPlan _buildPlan() => NutritionPlan(
        trainingTargets: _training,
        restTargets: _rest,
        mealBudgets: _budgets,
        breakfast: _breakfast,
        lunch: _lunch,
        dinner: _dinner,
        snacks: _snacks,
        smoothies: _smoothies,
        guidelines: _guidelines.text.trim().isEmpty ? null : _guidelines.text.trim(),
      );

  Future<void> _save() async {
    final plan = _buildPlan();
    if (widget.clientId != null) {
      ref.read(trainerClientRecordsProvider.notifier).update(widget.clientId!, (r) => r.copyWith(nutrition: plan));
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    final name = await _promptName(context);
    if (name == null || name.trim().isEmpty) return;
    ref.read(nutritionLibraryProvider.notifier).add(NutritionLibraryEntry(id: DateTime.now().microsecondsSinceEpoch.toString(), name: name.trim(), plan: plan));
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _guidelines.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("Training Day Targets"),
          _TargetsCard(targets: _training, onChange: (t) => setState(() => _training = t)),
          const SizedBox(height: 4),
          const SectionLabel("Rest Day Targets"),
          _TargetsCard(targets: _rest, onChange: (t) => setState(() => _rest = t)),
          const SizedBox(height: 4),
          const SectionLabel("Calorie Budget by Meal"),
          AppCard(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _mealCategories
                  .map((c) => SizedBox(
                        width: 100,
                        child: MiniField(label: c.$2, value: _budgets[c.$1] ?? "", ph: "kcal", onChange: (v) => setState(() => _budgets = {..._budgets, c.$1: v})),
                      ))
                  .toList(),
            ),
          ),
          for (final cat in _mealCategories) ...[
            const SizedBox(height: 4),
            SectionLabel(cat.$2),
            ..._listFor(cat.$1).asMap().entries.map((entry) => AppCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.value.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text("${entry.value.calories} kcal · P${entry.value.protein.toStringAsFixed(0)} C${entry.value.carbs.toStringAsFixed(0)} F${entry.value.fats.toStringAsFixed(0)}", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _setListFor(cat.$1, [..._listFor(cat.$1)]..removeAt(entry.key)),
                        icon: const Icon(LucideIcons.trash2, size: 14, color: Color(0xFF6B3B3B)),
                      ),
                    ],
                  ),
                )),
            BtnGhost(full: true, onPressed: () => _addMeal(cat.$1), child: Text("+ Add ${cat.$2.toLowerCase()}")),
          ],
          const SizedBox(height: 4),
          const SectionLabel("Guidelines & Notes"),
          TextField(
            controller: _guidelines,
            maxLines: 4,
            style: const TextStyle(color: AppColors.txt, fontSize: 13),
            decoration: InputDecoration(
              hintText: "Free-text coaching guidance for this client…",
              hintStyle: const TextStyle(color: AppColors.mute),
              filled: true,
              fillColor: AppColors.card,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.gold)),
            ),
          ),
          const SizedBox(height: 16),
          BtnGold(full: true, onPressed: _save, child: const Text("Save nutrition program")),
        ],
      ),
    );
  }
}

Future<String?> _promptName(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      title: const Text("Nutrition program name"),
      content: AppField(controller: controller, placeholder: "e.g. Cutting Phase — 1800 kcal"),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Cancel")),
        TextButton(onPressed: () => Navigator.of(ctx).pop(controller.text), child: const Text("Save")),
      ],
    ),
  );
}

class _TargetsCard extends StatelessWidget {
  const _TargetsCard({required this.targets, required this.onChange});
  final MacroTargets targets;
  final ValueChanged<MacroTargets> onChange;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: MiniField(label: "Calories", value: targets.calories ?? "", ph: "kcal", onChange: (v) => onChange(MacroTargets(calories: v, protein: targets.protein, carbs: targets.carbs, fats: targets.fats, water: targets.water)))),
              const SizedBox(width: 6),
              Expanded(child: MiniField(label: "Protein", value: targets.protein ?? "", ph: "g", onChange: (v) => onChange(MacroTargets(calories: targets.calories, protein: v, carbs: targets.carbs, fats: targets.fats, water: targets.water)))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: MiniField(label: "Carbs", value: targets.carbs ?? "", ph: "g", onChange: (v) => onChange(MacroTargets(calories: targets.calories, protein: targets.protein, carbs: v, fats: targets.fats, water: targets.water)))),
              const SizedBox(width: 6),
              Expanded(child: MiniField(label: "Fats", value: targets.fats ?? "", ph: "g", onChange: (v) => onChange(MacroTargets(calories: targets.calories, protein: targets.protein, carbs: targets.carbs, fats: v, water: targets.water)))),
              const SizedBox(width: 6),
              Expanded(child: MiniField(label: "Water", value: targets.water ?? "", ph: "oz", onChange: (v) => onChange(MacroTargets(calories: targets.calories, protein: targets.protein, carbs: targets.carbs, fats: targets.fats, water: v)))),
            ],
          ),
        ],
      ),
    );
  }
}
