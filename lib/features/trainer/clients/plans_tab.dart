import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/saved_program.dart";
import "../../../data/providers/platform_settings_provider.dart";
import "../../../data/providers/trainer_providers.dart";
import "../programs/nutrition_builder_screen.dart";
import "../programs/program_builder_screen.dart";

/// Mirrors PlansArea.jsx — 3 sub-tabs: Training (ProgramBuilder, shown
/// inline — no separate "build" gate), Nutrition (NutritionBuilder),
/// Programs (this client's assigned programs + the shared template
/// library, with Assign/Delete). Gated entirely behind "Coaches can edit
/// client workouts" (Settings → Customize Platform → Coaches) for a
/// non-owner coach — the owner can always edit.
class PlansTab extends ConsumerStatefulWidget {
  const PlansTab({super.key, required this.clientId});

  final String clientId;

  @override
  ConsumerState<PlansTab> createState() => _PlansTabState();
}

class _PlansTabState extends ConsumerState<PlansTab> {
  String _sub = "training";
  bool _buildingNutrition = false;

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(trainerClientRecordsProvider);
    final record = records[widget.clientId];
    if (record == null) return const SizedBox.shrink();

    final isOwner = ref.watch(trainerAuthProvider) == "owner";
    final canEdit = isOwner || ref.watch(platformSettingsProvider).coachCanEditClientWorkouts;
    if (!canEdit) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: HintBox(
          text: "Workout and nutrition program editing is turned off for coaches right now — the owner can turn it "
              "back on in Settings → Customize Platform, or edit this client's programs from the owner account.",
        ),
      );
    }

    if (_buildingNutrition) {
      return NutritionBuilderScreen(clientId: widget.clientId, existing: record.nutrition);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [("training", "Training"), ("nutrition", "Nutrition"), ("programs", "Programs")]
                  .map((t) => Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _sub = t.$1),
                          borderRadius: BorderRadius.circular(7),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: _sub == t.$1 ? AppColors.gold.withValues(alpha: 0.15) : Colors.transparent, borderRadius: BorderRadius.circular(7)),
                            child: Text(t.$2, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _sub == t.$1 ? AppColors.gold : AppColors.mute)),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
        Expanded(
          child: switch (_sub) {
            "training" => ProgramBuilderScreen(clientId: widget.clientId),
            "nutrition" => SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (record.nutrition == null)
                      const HintBox(text: "No nutrition program assigned yet.")
                    else
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Assigned nutrition program", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            const SizedBox(height: 4),
                            Text("Training target: ${record.nutrition!.trainingTargets.calories ?? '—'} kcal", style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                            Text("Rest target: ${record.nutrition!.restTargets.calories ?? '—'} kcal", style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    BtnGold(full: true, onPressed: () => setState(() => _buildingNutrition = true), child: const Text("Build / Edit Nutrition")),
                  ],
                ),
              ),
            _ => SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: _ProgramsLibrarySection(clientId: widget.clientId, record: record),
              ),
          },
        ),
      ],
    );
  }
}

class _ProgramsLibrarySection extends ConsumerWidget {
  const _ProgramsLibrarySection({required this.clientId, required this.record});
  final String clientId;
  final dynamic record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workoutLibrary = ref.watch(programsLibraryProvider);
    final nutritionLibrary = ref.watch(nutritionLibraryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel("Training Templates"),
        if (workoutLibrary.isEmpty) const HintBox(text: "No saved templates yet. Build a program and it'll appear here too."),
        ...workoutLibrary.map((p) => AppCard(
              child: Row(
                children: [
                  Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  TextButton(
                    onPressed: () async {
                      final assigned = SavedProgram(id: DateTime.now().microsecondsSinceEpoch.toString(), name: p.name, programDays: p.programDays);
                      final current = ref.read(trainerClientRecordsProvider)[clientId]!;
                      final nextSaved = [...current.savedPrograms, assigned];
                      try {
                        await SupabaseService.updateClientSavedPrograms(clientId, nextSaved);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't assign — check your connection and try again.")));
                        }
                        return;
                      }
                      ref.read(trainerClientRecordsProvider.notifier).update(clientId, (r) => r.copyWith(savedPrograms: nextSaved));
                    },
                    child: const Text("Assign", style: TextStyle(fontSize: 12, color: AppColors.gold)),
                  ),
                  IconButton(
                    onPressed: () async {
                      try {
                        await SupabaseService.deleteProgramLibraryEntry(p.id);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't delete — check your connection and try again.")));
                        }
                        return;
                      }
                      ref.read(programsLibraryProvider.notifier).remove(p.id);
                    },
                    icon: const Icon(LucideIcons.trash2, size: 14, color: Color(0xFF6B3B3B)),
                  ),
                ],
              ),
            )),
        const SizedBox(height: 12),
        const SectionLabel("Nutrition Templates"),
        if (nutritionLibrary.isEmpty) const HintBox(text: "No saved nutrition templates yet."),
        ...nutritionLibrary.map((e) => AppCard(
              child: Row(
                children: [
                  Expanded(child: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  TextButton(
                    onPressed: () => ref.read(trainerClientRecordsProvider.notifier).update(clientId, (r) => r.copyWith(nutrition: e.plan)),
                    child: const Text("Assign", style: TextStyle(fontSize: 12, color: AppColors.gold)),
                  ),
                  IconButton(onPressed: () => ref.read(nutritionLibraryProvider.notifier).remove(e.id), icon: const Icon(LucideIcons.trash2, size: 14, color: Color(0xFF6B3B3B))),
                ],
              ),
            )),
      ],
    );
  }
}
