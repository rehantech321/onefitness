import "package:flutter/material.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/meal_def.dart";

/// Mirrors CustomMealForm.jsx, trimmed to manual macro entry (no
/// per-ingredient qty/macro auto-computation) — name, ingredients as a
/// simple list, instructions, manual macros, diet tags.
class CustomMealForm extends StatefulWidget {
  const CustomMealForm({super.key, required this.mealType, required this.onCancel, required this.onSave});

  final String mealType;
  final VoidCallback onCancel;
  final ValueChanged<MealDef> onSave;

  @override
  State<CustomMealForm> createState() => _CustomMealFormState();
}

class _CustomMealFormState extends State<CustomMealForm> {
  final _name = TextEditingController();
  final _ingredients = TextEditingController();
  final _instructions = TextEditingController();
  final _calories = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fats = TextEditingController();
  final Set<String> _tags = {};

  @override
  void dispose() {
    _name.dispose();
    _ingredients.dispose();
    _instructions.dispose();
    _calories.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fats.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onCancel, title: "Create Custom Meal"),
          const SizedBox(height: 12),
          FieldLabeled(label: "Name", child: AppField(controller: _name)),
          const SizedBox(height: 10),
          FieldLabeled(label: "Ingredients (one per line)", child: TextField(
            controller: _ingredients,
            maxLines: 4,
            style: const TextStyle(color: AppColors.txt, fontSize: 13),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.bg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.gold)),
            ),
          )),
          const SizedBox(height: 10),
          FieldLabeled(label: "Instructions (optional)", child: AppField(controller: _instructions)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: MiniField(label: "Calories", value: _calories.text, ph: "0", onChange: (v) => _calories.text = v)),
              const SizedBox(width: 6),
              Expanded(child: MiniField(label: "Protein (g)", value: _protein.text, ph: "0", onChange: (v) => _protein.text = v)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: MiniField(label: "Carbs (g)", value: _carbs.text, ph: "0", onChange: (v) => _carbs.text = v)),
              const SizedBox(width: 6),
              Expanded(child: MiniField(label: "Fats (g)", value: _fats.text, ph: "0", onChange: (v) => _fats.text = v)),
            ],
          ),
          const SizedBox(height: 10),
          const Text("DIET TAGS", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: kDietTags.map((t) {
              final on = _tags.contains(t);
              return InkWell(
                onTap: () => setState(() => on ? _tags.remove(t) : _tags.add(t)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  decoration: BoxDecoration(color: on ? AppColors.gold.withValues(alpha: 0.15) : AppColors.card, border: Border.all(color: on ? AppColors.gold : AppColors.line), borderRadius: BorderRadius.circular(7)),
                  child: Text(t, style: TextStyle(fontSize: 11, color: on ? AppColors.gold : AppColors.mute)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          BtnGold(
            full: true,
            onPressed: _name.text.trim().isEmpty
                ? null
                : () => widget.onSave(MealDef(
                      id: "custom-${DateTime.now().microsecondsSinceEpoch}",
                      name: _name.text.trim(),
                      mealType: widget.mealType,
                      calories: int.tryParse(_calories.text.trim()) ?? 0,
                      protein: double.tryParse(_protein.text.trim()) ?? 0,
                      carbs: double.tryParse(_carbs.text.trim()) ?? 0,
                      fats: double.tryParse(_fats.text.trim()) ?? 0,
                      ingredients: _ingredients.text.split("\n").map((l) => l.trim()).where((l) => l.isNotEmpty).toList(),
                      instructions: _instructions.text.trim().isEmpty ? null : _instructions.text.trim(),
                      dietTags: _tags.toList(),
                      isCustom: true,
                    )),
            child: const Text("Save meal"),
          ),
        ],
      ),
    );
  }
}
