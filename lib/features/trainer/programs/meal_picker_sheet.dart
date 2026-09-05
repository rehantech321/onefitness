import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/meal_def.dart";
import "../../../data/providers/trainer_providers.dart";
import "custom_meal_form.dart";

/// Mirrors MealPicker.jsx — browse the built-in + coach-custom meal
/// database, filterable by diet tag, with a "Create Custom Meal" escape
/// hatch that routes to CustomMealForm.
Future<MealDef?> showMealPickerSheet(BuildContext context, String mealType) {
  return showModalBottomSheet<MealDef>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => SizedBox(height: 560, child: _MealPickerBody(mealType: mealType)),
  );
}

class _MealPickerBody extends ConsumerStatefulWidget {
  const _MealPickerBody({required this.mealType});
  final String mealType;

  @override
  ConsumerState<_MealPickerBody> createState() => _MealPickerBodyState();
}

class _MealPickerBodyState extends ConsumerState<_MealPickerBody> {
  final _search = TextEditingController();
  final Set<String> _tags = {};
  bool _creating = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_creating) {
      // A sub-view inside a real showModalBottomSheet — the shell's own
      // back handling (LocalBackScope) can't see into a Navigator route,
      // so without this PopScope, hardware back/an OS edge-swipe would
      // dismiss the whole sheet instead of just backing out of this form.
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _creating = false);
        },
        child: CustomMealForm(
          mealType: widget.mealType,
          onCancel: () => setState(() => _creating = false),
          onSave: (meal) {
            // Optimistic: pop immediately so the nutrition builder flow this
            // meal was created from isn't blocked on a round-trip. Best-effort
            // persist — on failure the meal just won't be in the shared
            // catalog on the next reload, no local state to unwind (`ref`
            // isn't safe to touch after this widget is popped/disposed).
            ref.read(customMealsProvider.notifier).add(meal);
            Navigator.of(context).pop(meal);
            SupabaseService.insertCustomMeal(meal).catchError((Object e) {
              // ignore: avoid_print
              print("[meal_picker_sheet] failed to persist custom meal: $e");
            });
          },
        ),
      );
    }

    final catalog = [...ref.watch(mealCatalogProvider), ...ref.watch(customMealsProvider)].where((m) => m.mealType == widget.mealType).toList();
    final q = _search.text.trim().toLowerCase();
    final visible = catalog.where((m) {
      if (q.isNotEmpty && !m.name.toLowerCase().contains(q)) return false;
      if (_tags.isNotEmpty && !_tags.every((t) => m.dietTags.contains(t))) return false;
      return true;
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionLabel("Pick a Meal"),
              TextButton(onPressed: () => setState(() => _creating = true), child: const Text("Create Custom Meal", style: TextStyle(color: AppColors.gold, fontSize: 12))),
            ],
          ),
          AppField(controller: _search, placeholder: "Search…", onChanged: (_) => setState(() {})),
          const SizedBox(height: 8),
          SizedBox(
            height: 30,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: kDietTags.map((t) {
                final on = _tags.contains(t.$1);
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: () => setState(() => on ? _tags.remove(t.$1) : _tags.add(t.$1)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(color: on ? AppColors.gold.withValues(alpha: 0.15) : AppColors.card, border: Border.all(color: on ? AppColors.gold : AppColors.line), borderRadius: BorderRadius.circular(14)),
                      child: Text(t.$2, style: TextStyle(fontSize: 10, color: on ? AppColors.gold : AppColors.mute)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: visible.isEmpty
                ? const HintBox(text: "No meals match — try Create Custom Meal.")
                : ListView(
                    children: visible
                        .map((m) => AppCard(
                              onTap: () => Navigator.of(context).pop(m),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                        Text("${m.calories} kcal · P${m.protein.toStringAsFixed(0)} C${m.carbs.toStringAsFixed(0)} F${m.fats.toStringAsFixed(0)}", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}
