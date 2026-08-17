import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/nutrition_helpers.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/meal_def.dart";
import "../../../data/models/nutrition_plan.dart";

class _IngredientRow {
  _IngredientRow({required this.id});
  final String id;
  final item = TextEditingController();
  final qty = TextEditingController();
  final unit = TextEditingController();
  String category = "pantry";

  void dispose() {
    item.dispose();
    qty.dispose();
    unit.dispose();
  }
}

/// Mirrors CustomMealForm.jsx — a from-scratch meal with structured
/// ingredient rows (live macro calc when quantities are numeric, falling
/// back to manually-entered totals), instructions, diet tags, notes.
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
  final _instructions = TextEditingController();
  final _calories = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fats = TextEditingController();
  final _notes = TextEditingController();
  final Set<String> _tags = {};
  late List<_IngredientRow> _rows = [_IngredientRow(id: _uid())];
  String? _err;

  static String _uid() => DateTime.now().microsecondsSinceEpoch.toString();

  @override
  void dispose() {
    _name.dispose();
    _instructions.dispose();
    _calories.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fats.dispose();
    _notes.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  List<Ingredient> get _liveIngredients => _rows
      .where((r) => r.item.text.trim().isNotEmpty)
      .map((r) => Ingredient(item: r.item.text.trim(), qty: num.tryParse(r.qty.text.trim()), unit: r.unit.text.trim(), category: r.category))
      .toList();

  @override
  Widget build(BuildContext context) {
    final liveMacros = computeMacrosFromIngredients(_liveIngredients);
    final displayCalories = liveMacros?.calories ?? int.tryParse(_calories.text.trim()) ?? 0;
    final displayProtein = liveMacros?.protein ?? double.tryParse(_protein.text.trim()) ?? 0;
    final displayCarbs = liveMacros?.carbs ?? double.tryParse(_carbs.text.trim()) ?? 0;
    final displayFats = liveMacros?.fats ?? double.tryParse(_fats.text.trim()) ?? 0;

    void submit() {
      if (_name.text.trim().isEmpty) {
        setState(() => _err = "Meal name is required.");
        return;
      }
      final clean = _rows.where((r) => r.item.text.trim().isNotEmpty).toList();
      if (clean.isEmpty) {
        setState(() => _err = "Add at least one ingredient.");
        return;
      }
      final macros = computeMacrosFromIngredients(_liveIngredients);
      widget.onSave(MealDef(
        id: "custom-${DateTime.now().microsecondsSinceEpoch}",
        name: _name.text.trim(),
        mealType: widget.mealType,
        calories: macros?.calories ?? int.tryParse(_calories.text.trim()) ?? 0,
        protein: macros?.protein ?? double.tryParse(_protein.text.trim()) ?? 0,
        carbs: macros?.carbs ?? double.tryParse(_carbs.text.trim()) ?? 0,
        fats: macros?.fats ?? double.tryParse(_fats.text.trim()) ?? 0,
        ingredients: clean.map((r) => Ingredient(item: r.item.text.trim(), qty: num.tryParse(r.qty.text.trim()), unit: r.unit.text.trim(), category: r.category)).toList(),
        instructions: _instructions.text.trim().isEmpty ? null : _instructions.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        dietTags: _tags.isNotEmpty ? {"omnivore", ..._tags}.toList() : const ["omnivore"],
        isCustom: true,
      ));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onCancel, title: "Create Custom Meal"),
          const SizedBox(height: 12),
          FieldLabeled(label: "Meal name *", child: AppField(controller: _name, placeholder: "e.g. Protein Pancakes")),
          const SizedBox(height: 14),
          const Text("INGREDIENTS *", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
          const SizedBox(height: 8),
          ..._rows.map((row) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 3, child: AppField(controller: row.item, placeholder: "Ingredient", onChanged: (_) => setState(() {}))),
                    const SizedBox(width: 5),
                    Expanded(child: AppField(controller: row.qty, placeholder: "Qty", keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}))),
                    const SizedBox(width: 5),
                    Expanded(child: AppField(controller: row.unit, placeholder: "Unit")),
                    IconButton(
                      onPressed: _rows.length == 1 ? null : () => setState(() {
                            row.dispose();
                            _rows = _rows.where((r) => r.id != row.id).toList();
                          }),
                      icon: const Icon(LucideIcons.x, size: 16, color: Color(0xFF6B3B3B)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32),
                    ),
                  ],
                ),
              )),
          // Mirrors CustomMealForm.jsx's "last row's category" selector — the
          // category picked here applies to whichever ingredient row was
          // added most recently.
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(8)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _rows.last.category,
                isExpanded: true,
                dropdownColor: AppColors.card,
                style: const TextStyle(fontSize: 12, color: AppColors.mute),
                items: kIngredientCategories.map((c) => DropdownMenuItem(value: c.$1, child: Text("Last row's category: ${c.$2}"))).toList(),
                onChanged: (v) => setState(() => _rows.last.category = v ?? _rows.last.category),
              ),
            ),
          ),
          OutlinedButton(
            onPressed: () => setState(() => _rows = [..._rows, _IngredientRow(id: _uid())]),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.gold, side: BorderSide(color: AppColors.line, style: BorderStyle.solid), padding: const EdgeInsets.symmetric(vertical: 8)),
            child: const Text("+ Add ingredient", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 14),
          if (displayCalories > 0 || displayProtein > 0)
            Row(
              children: [
                Expanded(child: _MacroBox(label: "CAL", value: "$displayCalories")),
                const SizedBox(width: 8),
                Expanded(child: _MacroBox(label: "PG", value: fmtQty(displayProtein))),
                const SizedBox(width: 8),
                Expanded(child: _MacroBox(label: "CG", value: fmtQty(displayCarbs))),
                const SizedBox(width: 8),
                Expanded(child: _MacroBox(label: "FG", value: fmtQty(displayFats))),
              ],
            ),
          const SizedBox(height: 14),
          FieldLabeled(
            label: "Preparation instructions",
            child: TextField(
              controller: _instructions,
              maxLines: 4,
              style: const TextStyle(color: AppColors.txt, fontSize: 13),
              decoration: InputDecoration(
                hintText: "Step-by-step prep…",
                hintStyle: const TextStyle(color: AppColors.mute),
                filled: true,
                fillColor: AppColors.bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.gold)),
              ),
            ),
          ),
          if (liveMacros == null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: MiniField(label: "Calories (kcal)", value: _calories.text, onChange: (v) => setState(() => _calories.text = v))),
                const SizedBox(width: 8),
                Expanded(child: MiniField(label: "Protein (g)", value: _protein.text, onChange: (v) => setState(() => _protein.text = v))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: MiniField(label: "Carbs (g)", value: _carbs.text, onChange: (v) => setState(() => _carbs.text = v))),
                const SizedBox(width: 8),
                Expanded(child: MiniField(label: "Fats (g)", value: _fats.text, onChange: (v) => setState(() => _fats.text = v))),
              ],
            ),
          ],
          const SizedBox(height: 14),
          const Text("DIET TAGS", style: TextStyle(fontSize: 11, color: AppColors.mute, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: kDietTags.map((t) {
              final on = _tags.contains(t.$1);
              return InkWell(
                onTap: () => setState(() => on ? _tags.remove(t.$1) : _tags.add(t.$1)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  decoration: BoxDecoration(color: on ? AppColors.gold.withValues(alpha: 0.15) : AppColors.card, border: Border.all(color: on ? AppColors.gold : AppColors.line), borderRadius: BorderRadius.circular(7)),
                  child: Text(t.$2, style: TextStyle(fontSize: 11, color: on ? AppColors.gold : AppColors.mute)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          FieldLabeled(
            label: "Notes (substitutions, modifications)",
            child: TextField(
              controller: _notes,
              maxLines: 3,
              style: const TextStyle(color: AppColors.txt, fontSize: 13),
              decoration: InputDecoration(
                hintText: "Optional…",
                hintStyle: const TextStyle(color: AppColors.mute),
                filled: true,
                fillColor: AppColors.bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.gold)),
              ),
            ),
          ),
          if (_err != null)
            Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, style: const TextStyle(color: Color(0xFFC97F7F), fontSize: 12))),
          const SizedBox(height: 16),
          BtnGold(
            full: true,
            onPressed: submit,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [Icon(LucideIcons.check, size: 15), SizedBox(width: 6), Text("Save Custom Meal")],
            ),
          ),
        ],
      ),
    );
  }
}

class _MacroBox extends StatelessWidget {
  const _MacroBox({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.goldDim), borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.gold)),
          Text(label, style: const TextStyle(fontSize: 9, color: AppColors.mute, letterSpacing: 0.5)),
        ],
      ),
    );
  }
}
