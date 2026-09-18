import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/nutrition_library_entry.dart";
import "../../../data/models/saved_program.dart";
import "../../../data/providers/trainer_providers.dart";
import "nutrition_builder_screen.dart";
import "program_builder_screen.dart";

/// What the drawer's "Build Workout Program" and "Build Nutrition Program"
/// open: the library of saved templates first, with a builder behind it.
///
/// Before this, both entries opened a bare builder. A saved workout went
/// into the library but nothing on the page showed it, and a saved
/// nutrition program was never persisted at all — so from the owner's seat
/// building a program looked like it did nothing.
enum LibraryKind { workout, nutrition }

class ProgramLibraryPage extends ConsumerStatefulWidget {
  const ProgramLibraryPage({super.key, required this.kind});
  final LibraryKind kind;

  @override
  ConsumerState<ProgramLibraryPage> createState() => _ProgramLibraryPageState();
}

class _ProgramLibraryPageState extends ConsumerState<ProgramLibraryPage> {
  /// Null = the list. Otherwise the builder is open — editing the given
  /// entry, or a fresh program when the id is empty.
  _Edit? _edit;

  void _close() => setState(() => _edit = null);

  Future<void> _delete(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Delete "$name"?'),
        content: const Text("Programs already assigned to clients keep their own copy. This only removes the template."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete")),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SupabaseService.deleteProgramLibraryEntry(id);
      if (widget.kind == LibraryKind.workout) {
        ref.read(programsLibraryProvider.notifier).remove(id);
      } else {
        ref.read(nutritionLibraryProvider.notifier).remove(id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't delete — check your connection and try again.")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final edit = _edit;
    final isWorkout = widget.kind == LibraryKind.workout;

    if (edit != null) {
      return LocalBackScope(
        isOpen: true,
        onBack: _close,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: BackBar(
                onBack: _close,
                title: edit.isNew ? (isWorkout ? "New workout program" : "New nutrition program") : edit.name,
              ),
            ),
            Expanded(
              child: isWorkout
                  ? ProgramBuilderScreen(key: ValueKey("w-${edit.id}"), libraryEntry: edit.workout, onSaved: _close)
                  : NutritionBuilderScreen(key: ValueKey("n-${edit.id}"), existing: edit.nutrition?.plan, libraryEntry: edit.nutrition, onSaved: _close),
            ),
          ],
        ),
      );
    }

    final workouts = ref.watch(programsLibraryProvider);
    final nutrition = ref.watch(nutritionLibraryProvider);
    final count = isWorkout ? workouts.length : nutrition.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(isWorkout ? "Workout Programs" : "Nutrition Programs"),
          const SizedBox(height: 4),
          Text(
            isWorkout
                ? "Templates you can assign to any client from their Plans tab. Tap one to edit it."
                : "Templates you can assign to any client from their Plans tab. Tap one to edit it.",
            style: const TextStyle(fontSize: 12, color: AppColors.mute, height: 1.4),
          ),
          const SizedBox(height: 14),
          BtnGold(
            full: true,
            onPressed: () => setState(() => _edit = _Edit.fresh()),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.plus, size: 15, color: Colors.white),
                const SizedBox(width: 6),
                Text(isWorkout ? "Build new workout program" : "Build new nutrition program"),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SectionLabel("Saved ($count)"),
          if (count == 0)
            HintBox(text: isWorkout ? "No workout programs saved yet — build the first one above." : "No nutrition programs saved yet — build the first one above.")
          else if (isWorkout)
            for (final p in workouts)
              _Row(
                title: p.name,
                subtitle: "${p.programDays.length} day${p.programDays.length == 1 ? '' : 's'}"
                    "${p.coachName != null ? ' · by ${p.coachName}' : ''}"
                    "${p.modifiedAt != null ? ' · ${p.modifiedAt}' : ''}",
                icon: LucideIcons.dumbbell,
                onTap: () => setState(() => _edit = _Edit.workout(p)),
                onDelete: () => _delete(p.id, p.name),
              )
          else
            for (final e in nutrition)
              _Row(
                title: e.name,
                subtitle: "${(e.plan.trainingTargets.calories ?? '').isNotEmpty ? '${e.plan.trainingTargets.calories} kcal training days' : 'No calorie target'}"
                    " · ${[e.plan.breakfast, e.plan.lunch, e.plan.dinner, e.plan.snacks, e.plan.smoothies].where((m) => m.isNotEmpty).length} meal groups",
                icon: LucideIcons.utensils,
                onTap: () => setState(() => _edit = _Edit.nutrition(e)),
                onDelete: () => _delete(e.id, e.name),
              ),
        ],
      ),
    );
  }
}

class _Edit {
  _Edit._({required this.id, required this.name, this.workout, this.nutrition});
  factory _Edit.fresh() => _Edit._(id: "", name: "");
  factory _Edit.workout(SavedProgram p) => _Edit._(id: p.id, name: p.name, workout: p);
  factory _Edit.nutrition(NutritionLibraryEntry e) => _Edit._(id: e.id, name: e.name, nutrition: e);
  final String id;
  final String name;
  final SavedProgram? workout;
  final NutritionLibraryEntry? nutrition;
  bool get isNew => id.isEmpty;
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.subtitle, required this.icon, required this.onTap, required this.onDelete});
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.mute)),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(LucideIcons.trash2, size: 15, color: AppColors.errorText),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          const Icon(LucideIcons.chevronRight, size: 15, color: AppColors.mute),
        ],
      ),
    );
  }
}
