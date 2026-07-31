import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/exercise_def.dart";
import "../../../data/providers/trainer_providers.dart";

/// Mirrors ExercisePicker.jsx — search/browse-by-muscle-group over the
/// exercise catalog, with a "Custom exercise" free-text fallback.
Future<ExerciseDef?> showExercisePickerSheet(BuildContext context) {
  return showModalBottomSheet<ExerciseDef>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => const SizedBox(height: 560, child: _ExercisePickerBody()),
  );
}

class _ExercisePickerBody extends ConsumerStatefulWidget {
  const _ExercisePickerBody();

  @override
  ConsumerState<_ExercisePickerBody> createState() => _ExercisePickerBodyState();
}

class _ExercisePickerBodyState extends ConsumerState<_ExercisePickerBody> {
  final _search = TextEditingController();
  String? _muscleFilter;
  bool _custom = false;
  final _customName = TextEditingController();
  String _customGroup = kMuscleGroups.first;

  @override
  void dispose() {
    _search.dispose();
    _customName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_custom) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BackBar(onBack: () => setState(() => _custom = false), title: "Custom Exercise"),
            const SizedBox(height: 12),
            FieldLabeled(label: "Name", child: AppField(controller: _customName)),
            const SizedBox(height: 10),
            const Text("MUSCLE GROUP", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: kMuscleGroups.map((g) {
                final selected = _customGroup == g;
                return InkWell(
                  onTap: () => setState(() => _customGroup = g),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.bg,
                      border: Border.all(color: selected ? AppColors.gold : AppColors.line),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(g, style: TextStyle(fontSize: 11, color: selected ? AppColors.gold : AppColors.txt)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            BtnGold(
              full: true,
              onPressed: _customName.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(ExerciseDef(id: "custom-${DateTime.now().microsecondsSinceEpoch}", name: _customName.text.trim(), movementPattern: "Isolation", primaryMuscle: _customGroup)),
              child: const Text("Add"),
            ),
          ],
        ),
      );
    }

    final catalog = ref.watch(exerciseCatalogProvider);
    final q = _search.text.trim().toLowerCase();
    final visible = catalog.where((e) {
      if (_muscleFilter != null && e.primaryMuscle != _muscleFilter) return false;
      if (q.isEmpty) return true;
      return e.name.toLowerCase().contains(q) || e.movementPattern.toLowerCase().contains(q) || e.primaryMuscle.toLowerCase().contains(q) || e.equipment.any((eq) => eq.toLowerCase().contains(q));
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionLabel("Pick an Exercise"),
              TextButton(onPressed: () => setState(() => _custom = true), child: const Text("Custom", style: TextStyle(color: AppColors.gold, fontSize: 12))),
            ],
          ),
          AppField(controller: _search, placeholder: "Search…", onChanged: (_) => setState(() {})),
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _MuscleChip(label: "All", selected: _muscleFilter == null, onTap: () => setState(() => _muscleFilter = null)),
                ...kMuscleGroups.map((g) => _MuscleChip(label: g, selected: _muscleFilter == g, onTap: () => setState(() => _muscleFilter = g))),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: visible.isEmpty
                ? const HintBox(text: "No exercises match — try Custom to add one.")
                : ListView(
                    children: visible
                        .map((e) => AppCard(
                              onTap: () => Navigator.of(context).pop(e),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                        Text(e.primaryMuscle, style: const TextStyle(fontSize: 11, color: AppColors.mute)),
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

class _MuscleChip extends StatelessWidget {
  const _MuscleChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.card,
            border: Border.all(color: selected ? AppColors.gold : AppColors.line),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(label, style: TextStyle(fontSize: 11, color: selected ? AppColors.gold : AppColors.mute)),
        ),
      ),
    );
  }
}
