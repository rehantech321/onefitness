import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/client_record.dart";
import "../../../data/models/nutrition_plan.dart";
import "../../../data/models/saved_program.dart";
import "../../../data/providers/trainer_providers.dart";
import "../programs/nutrition_builder_screen.dart";
import "../programs/program_builder_screen.dart";
import "../schedule/client_search_picker.dart";

/// Mirrors PlansArea.jsx — 3 sub-tabs: Training (ProgramBuilder, shown
/// inline — no separate "build" gate), Nutrition (NutritionBuilder),
/// Programs (this client's AI drafts + saved programs + the shared
/// template library — see ProgramsPanel.jsx). Owner-only, no exceptions —
/// generating, approving, or assigning a workout/nutrition program is a
/// hard owner-exclusive capability, same as Reports/Memberships/Waivers.
class PlansTab extends ConsumerStatefulWidget {
  const PlansTab({super.key, required this.clientId});

  final String clientId;

  @override
  ConsumerState<PlansTab> createState() => _PlansTabState();
}

class _PlansTabState extends ConsumerState<PlansTab> {
  String _sub = "training";

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(trainerClientRecordsProvider);
    final record = records[widget.clientId];
    if (record == null) return const SizedBox.shrink();

    final isOwner = ref.watch(trainerAuthProvider) == "owner";
    if (!isOwner) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: HintBox(
          text: "Only the owner can build, approve, or assign workout and nutrition programs.",
        ),
      );
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
            "nutrition" => NutritionBuilderScreen(clientId: widget.clientId, existing: record.nutrition),
            _ => SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: _ProgramsPanel(
                  clientId: widget.clientId,
                  record: record,
                  onEditWorkout: () => setState(() => _sub = "training"),
                  onEditNutrition: () => setState(() => _sub = "nutrition"),
                ),
              ),
          },
        ),
      ],
    );
  }
}

/// Mirrors ProgramsPanel.jsx — AI workout/nutrition draft review, this
/// client's own saved programs (Edit/Archive/Duplicate/Assign/Delete), and
/// the shared template library (Assign/Edit/Duplicate/Delete).
class _ProgramsPanel extends ConsumerStatefulWidget {
  const _ProgramsPanel({required this.clientId, required this.record, required this.onEditWorkout, required this.onEditNutrition});

  final String clientId;
  final ClientRecord record;
  final VoidCallback onEditWorkout;
  final VoidCallback onEditNutrition;

  @override
  ConsumerState<_ProgramsPanel> createState() => _ProgramsPanelState();
}

class _ProgramsPanelState extends ConsumerState<_ProgramsPanel> {
  bool _generatingWorkoutDraft = false;
  bool _regeneratingWorkoutDraft = false;
  bool _generatingNutritionDraft = false;
  bool _regeneratingNutritionDraft = false;
  bool _busy = false;
  String? _error;
  String _libraryTab = "training";

  ClientRecord get _record => ref.watch(trainerClientRecordsProvider)[widget.clientId] ?? widget.record;

  void _showAlert(String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("OK"))],
      ),
    );
  }

  Future<bool> _confirm(String message, {String confirmLabel = "Confirm"}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(confirmLabel)),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _refreshClient() async {
    try {
      final fresh = await SupabaseService.loadClientRecord(widget.clientId);
      ref.read(trainerClientRecordsProvider.notifier).update(widget.clientId, (_) => fresh);
    } catch (_) {}
  }

  // ── Workout AI draft ────────────────────────────────────────────────

  Future<void> _generateWorkoutDraft() async {
    setState(() => _generatingWorkoutDraft = true);
    try {
      final res = await SupabaseService.generateAiWorkoutProgram(widget.clientId);
      if (res["ok"] == false) {
        _showAlert(res["reason"] == "intakes-incomplete" ? "The Personalized Training Intake isn't marked complete yet." : "A workout program already exists for this client.");
      }
    } catch (e) {
      _showAlert(e.toString().replaceFirst("Exception: ", ""));
    }
    await _refreshClient();
    if (mounted) setState(() => _generatingWorkoutDraft = false);
  }

  Future<void> _regenerateWorkoutDraft() async {
    final ok = await _confirm(
      "Draft a fresh workout program from this client's current Personalized Training Intake answers? This creates a new draft to review — nothing changes until you approve it.",
      confirmLabel: "Draft fresh workout",
    );
    if (!ok) return;
    setState(() => _regeneratingWorkoutDraft = true);
    try {
      await SupabaseService.generateAiWorkoutProgram(widget.clientId, forceRegenerate: true);
    } catch (e) {
      _showAlert(e.toString().replaceFirst("Exception: ", ""));
    }
    await _refreshClient();
    if (mounted) setState(() => _regeneratingWorkoutDraft = false);
  }

  Future<void> _approveWorkoutDraft(SavedProgram draft) => _writeSavedPrograms(
        _record.savedPrograms.map((p) => p.id == draft.id ? p.copyWith(status: "active") : p).toList(),
      );

  Future<void> _discardWorkoutDraft(String id) => _writeSavedPrograms(_record.savedPrograms.where((p) => p.id != id).toList());

  Future<void> _editWorkout(SavedProgram p) async {
    setState(() => _busy = true);
    try {
      await SupabaseService.updateClientProgramDays(widget.clientId, p.programDays);
      ref.read(trainerClientRecordsProvider.notifier).update(widget.clientId, (r) => r.copyWith(programDays: p.programDays));
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
    widget.onEditWorkout();
  }

  Future<void> _writeSavedPrograms(List<SavedProgram> next) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SupabaseService.updateClientSavedPrograms(widget.clientId, next);
      ref.read(trainerClientRecordsProvider.notifier).update(widget.clientId, (r) => r.copyWith(savedPrograms: next));
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't save — check your connection and try again.");
    }
    if (mounted) setState(() => _busy = false);
  }

  // ── Nutrition AI draft ──────────────────────────────────────────────

  Future<void> _generateNutritionDraft() async {
    setState(() => _generatingNutritionDraft = true);
    try {
      final res = await SupabaseService.generateAiNutritionProgram(widget.clientId);
      if (res["ok"] == false) {
        _showAlert(res["reason"] == "nutrition-intake-incomplete" ? "The Nutrition Intake isn't marked complete yet." : "A draft already exists for this client.");
      }
    } catch (e) {
      _showAlert(e.toString().replaceFirst("Exception: ", ""));
    }
    await _refreshClient();
    if (mounted) setState(() => _generatingNutritionDraft = false);
  }

  Future<void> _regenerateNutritionDraft() async {
    final ok = await _confirm(
      "Draft fresh targets from this client's current Nutrition Intake answers? This creates a new draft to review — nothing changes until you apply it.",
      confirmLabel: "Draft fresh targets",
    );
    if (!ok) return;
    setState(() => _regeneratingNutritionDraft = true);
    try {
      await SupabaseService.generateAiNutritionProgram(widget.clientId, forceRegenerate: true);
    } catch (e) {
      _showAlert(e.toString().replaceFirst("Exception: ", ""));
    }
    await _refreshClient();
    if (mounted) setState(() => _regeneratingNutritionDraft = false);
  }

  Future<void> _approveNutritionDraft(NutritionProgramEntry draft) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final nextPrograms = _record.savedNutritionPrograms.map((p) => p.id == draft.id ? p.copyWith(status: "active") : p).toList();
      final nextPlan = (_record.nutrition ?? const NutritionPlan()).copyWith(
        trainingTargets: draft.trainingTargets,
        restTargets: draft.restTargets,
        mealBudgets: draft.mealBudgets,
        guidelines: draft.guidelines,
      );
      await SupabaseService.updateClientNutrition(widget.clientId, nextPlan);
      await SupabaseService.updateClientSavedNutritionPrograms(widget.clientId, nextPrograms);
      ref.read(trainerClientRecordsProvider.notifier).update(widget.clientId, (r) => r.copyWith(nutrition: nextPlan, savedNutritionPrograms: nextPrograms));
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't apply this draft — check your connection and try again.");
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _discardNutritionDraft(String id) => _writeSavedNutritionPrograms(_record.savedNutritionPrograms.where((p) => p.id != id).toList());

  Future<void> _writeSavedNutritionPrograms(List<NutritionProgramEntry> next) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SupabaseService.updateClientSavedNutritionPrograms(widget.clientId, next);
      ref.read(trainerClientRecordsProvider.notifier).update(widget.clientId, (r) => r.copyWith(savedNutritionPrograms: next));
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't save — check your connection and try again.");
    }
    if (mounted) setState(() => _busy = false);
  }

  // ── Assign to another client ────────────────────────────────────────

  Future<void> _assignWorkoutElsewhere(SavedProgram p) async {
    final target = await _pickClient();
    if (target == null) return;
    setState(() => _busy = true);
    try {
      final targetRecord = await SupabaseService.loadClientRecord(target.id);
      final copy = SavedProgram(
        id: "${DateTime.now().microsecondsSinceEpoch}",
        name: p.name,
        status: "active",
        coachName: p.coachName,
        programDays: p.programDays,
        createdAt: stamp(),
      );
      await SupabaseService.updateClientSavedPrograms(target.id, [...targetRecord.savedPrograms, copy]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Assigned to ${target.name}.")));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't assign — check your connection and try again.")));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _assignNutritionElsewhere(NutritionProgramEntry p) async {
    final target = await _pickClient();
    if (target == null) return;
    setState(() => _busy = true);
    try {
      final targetRecord = await SupabaseService.loadClientRecord(target.id);
      final copy = NutritionProgramEntry(
        id: "${DateTime.now().microsecondsSinceEpoch}",
        name: p.name,
        status: "active",
        source: "coach",
        trainingTargets: p.trainingTargets,
        restTargets: p.restTargets,
        mealBudgets: p.mealBudgets,
        guidelines: p.guidelines,
        createdAt: stamp(),
      );
      await SupabaseService.updateClientSavedNutritionPrograms(target.id, [...targetRecord.savedNutritionPrograms, copy]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Assigned to ${target.name}.")));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't assign — check your connection and try again.")));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<dynamic> _pickClient() {
    final roster = ref.read(trainerRosterProvider);
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 18, right: 18, top: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel("Assign to another client"),
            const SizedBox(height: 8),
            ClientSearchPicker(roster: roster, exclude: [widget.clientId], onSelect: (c) => Navigator.of(ctx).pop(c)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final record = _record;
    final workoutDrafts = record.savedPrograms.where((p) => p.source == "ai" && p.status == "draft").toList();
    final workoutPrograms = record.savedPrograms.where((p) => !(p.source == "ai" && p.status == "draft")).toList();
    final nutritionDrafts = record.savedNutritionPrograms.where((p) => p.source == "ai" && p.status == "draft").toList();
    final nutritionPrograms = record.savedNutritionPrograms.where((p) => !(p.source == "ai" && p.status == "draft")).toList();
    final hasAnyAiWorkout = record.savedPrograms.any((p) => p.source == "ai");
    final hasAnyAiNutrition = record.savedNutritionPrograms.any((p) => p.source == "ai");
    final workoutLibrary = ref.watch(programsLibraryProvider);
    final nutritionLibrary = ref.watch(nutritionLibraryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: const TextStyle(color: Color(0xFFC97F7F), fontSize: 12))),

        // ── AI workout draft ──
        if (workoutDrafts.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(hasAnyAiWorkout ? "Regenerate from their Training Intake" : "Draft a workout with AI", style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                    const SizedBox(width: 6),
                    const Tag(text: "AI", gold: true),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  hasAnyAiWorkout
                      ? "If this client has updated their Personalized Training Intake answers, draft a fresh split from their current answers. You'll review it here before anything changes."
                      : "This client's Personalized Training Intake is complete but no AI draft has been generated yet. Draft a weekly split from their intake answers — you'll review it here before assigning it.",
                  style: const TextStyle(fontSize: 12, color: AppColors.mute, height: 1.5),
                ),
                const SizedBox(height: 10),
                BtnGold(
                  full: true,
                  onPressed: (_generatingWorkoutDraft || _regeneratingWorkoutDraft) ? null : (hasAnyAiWorkout ? _regenerateWorkoutDraft : _generateWorkoutDraft),
                  child: Text(_generatingWorkoutDraft || _regeneratingWorkoutDraft
                      ? "Generating…"
                      : hasAnyAiWorkout
                          ? "Regenerate AI Workout Draft"
                          : "Draft a Workout with AI"),
                ),
              ],
            ),
          ),
        for (final p in workoutDrafts)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.08), border: Border.all(color: AppColors.goldDim), borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                    const SizedBox(width: 6),
                    const Tag(text: "AI Draft", gold: true),
                  ],
                ),
                const SizedBox(height: 6),
                Text("${p.programDays.length} day split${p.createdAt != null ? " · generated ${p.createdAt}" : ""}", style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                const SizedBox(height: 8),
                const HintBox(text: "Not visible to this client until you approve it. Review the days, edit anything that needs a coach's touch, then approve to assign it."),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: BtnGold(onPressed: _busy ? null : () => _editWorkout(p), child: const Text("Review & Edit"))),
                    const SizedBox(width: 6),
                    Expanded(child: BtnGold(onPressed: _busy ? null : () => _approveWorkoutDraft(p), child: const Text("Approve & Assign"))),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: BtnGhost(
                        onPressed: _regeneratingWorkoutDraft ? null : _regenerateWorkoutDraft,
                        child: Text(_regeneratingWorkoutDraft ? "Regenerating…" : "Regenerate"),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => _discardWorkoutDraft(p.id),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF6B3B3B)), foregroundColor: const Color(0xFFC97F7F)),
                        child: const Text("Discard"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

        // ── AI nutrition draft ──
        if (nutritionDrafts.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(hasAnyAiNutrition ? "Regenerate Nutrition Targets from Intake" : "Draft Nutrition Targets with AI", style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                    const SizedBox(width: 6),
                    const Tag(text: "AI", gold: true),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  hasAnyAiNutrition
                      ? "If this client has updated their Nutrition Intake answers since their targets were last set, draft a fresh set from their current answers. You'll review it here before anything changes."
                      : "This client's Nutrition Intake is complete but no AI draft has been generated yet. Draft whole-number Training/Rest Day targets from their intake answers — you'll review it here before anything is applied.",
                  style: const TextStyle(fontSize: 12, color: AppColors.mute, height: 1.5),
                ),
                const SizedBox(height: 10),
                BtnGold(
                  full: true,
                  onPressed: (_generatingNutritionDraft || _regeneratingNutritionDraft) ? null : (hasAnyAiNutrition ? _regenerateNutritionDraft : _generateNutritionDraft),
                  child: Text(_generatingNutritionDraft || _regeneratingNutritionDraft
                      ? "Generating…"
                      : hasAnyAiNutrition
                          ? "Regenerate AI Nutrition Targets"
                          : "Generate AI Nutrition Targets"),
                ),
              ],
            ),
          ),
        for (final p in nutritionDrafts)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.08), border: Border.all(color: AppColors.goldDim), borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text("AI-drafted calorie & macro targets are ready", style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                    const SizedBox(width: 6),
                    const Tag(text: "AI Draft", gold: true),
                  ],
                ),
                const SizedBox(height: 6),
                Text("Training: ${p.trainingTargets.calories ?? "—"} kcal", style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                Text("Rest: ${p.restTargets.calories ?? "—"} kcal", style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                const SizedBox(height: 8),
                const HintBox(text: "Approving fills in this client's Training/Rest Day Targets and Calorie Budget from this draft. Review it first if you'd like to adjust anything."),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: BtnGold(onPressed: _busy ? null : () => widget.onEditNutrition(), child: const Text("Review & Edit"))),
                    const SizedBox(width: 6),
                    Expanded(child: BtnGold(onPressed: _busy ? null : () => _approveNutritionDraft(p), child: const Text("Approve & Assign"))),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: BtnGhost(
                        onPressed: _regeneratingNutritionDraft ? null : _regenerateNutritionDraft,
                        child: Text(_regeneratingNutritionDraft ? "Regenerating…" : "Regenerate"),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => _discardNutritionDraft(p.id),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF6B3B3B)), foregroundColor: const Color(0xFFC97F7F)),
                        child: const Text("Discard"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

        // ── This client's own programs ──
        const SectionLabel("This Client's Workout Programs"),
        const SizedBox(height: 8),
        if (workoutPrograms.isEmpty) const Padding(padding: EdgeInsets.only(bottom: 16), child: HintBox(text: "No workout programs assigned yet."))
        else
          ...workoutPrograms.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ProgramCard(
                  name: p.name,
                  meta: "${p.programDays.length} day split · ${p.coachName ?? "—"}${p.createdAt != null ? " · ${p.createdAt}" : ""}",
                  modifiedLabel: p.modifiedAt != null ? "Modified ${p.modifiedAt}" : null,
                  archived: p.status == "archived",
                  busy: _busy,
                  onEdit: () => _editWorkout(p),
                  onArchiveToggle: () => _writeSavedPrograms(
                    _record.savedPrograms.map((x) => x.id == p.id ? x.copyWith(status: x.status == "archived" ? "active" : "archived") : x).toList(),
                  ),
                  onDuplicate: () => _writeSavedPrograms([
                    ..._record.savedPrograms,
                    SavedProgram(id: "${DateTime.now().microsecondsSinceEpoch}", name: "${p.name} (copy)", status: "active", coachName: p.coachName, programDays: p.programDays, createdAt: stamp()),
                  ]),
                  onAssign: () => _assignWorkoutElsewhere(p),
                  onDelete: () async {
                    if (!await _confirm("Delete \"${p.name}\"? This can't be undone.", confirmLabel: "Delete")) return;
                    await _writeSavedPrograms(_record.savedPrograms.where((x) => x.id != p.id).toList());
                  },
                ),
              )),

        const SizedBox(height: 6),
        const SectionLabel("This Client's Nutrition Programs"),
        const SizedBox(height: 8),
        if (nutritionPrograms.isEmpty) const Padding(padding: EdgeInsets.only(bottom: 16), child: HintBox(text: "No nutrition programs assigned yet."))
        else
          ...nutritionPrograms.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ProgramCard(
                  name: p.name,
                  meta: "${p.trainingTargets.calories ?? "—"} kcal/day · ${p.createdBy ?? "—"}${p.createdAt != null ? " · ${p.createdAt}" : ""}",
                  archived: p.status == "archived",
                  busy: _busy,
                  onEdit: () => widget.onEditNutrition(),
                  onArchiveToggle: () => _writeSavedNutritionPrograms(
                    _record.savedNutritionPrograms.map((x) => x.id == p.id ? x.copyWith(status: x.status == "archived" ? "active" : "archived") : x).toList(),
                  ),
                  onDuplicate: () => _writeSavedNutritionPrograms([
                    ..._record.savedNutritionPrograms,
                    NutritionProgramEntry(
                      id: "${DateTime.now().microsecondsSinceEpoch}",
                      name: "${p.name} (copy)",
                      status: "active",
                      source: "coach",
                      trainingTargets: p.trainingTargets,
                      restTargets: p.restTargets,
                      mealBudgets: p.mealBudgets,
                      guidelines: p.guidelines,
                      createdAt: stamp(),
                    ),
                  ]),
                  onAssign: () => _assignNutritionElsewhere(p),
                  onDelete: () async {
                    if (!await _confirm("Delete \"${p.name}\"? This can't be undone.", confirmLabel: "Delete")) return;
                    await _writeSavedNutritionPrograms(_record.savedNutritionPrograms.where((x) => x.id != p.id).toList());
                  },
                ),
              )),

        // ── Programs Library ──
        const SizedBox(height: 6),
        const SectionLabel("Programs Library"),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(3),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [("training", "Training"), ("nutrition", "Nutrition")]
                .map((t) => Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _libraryTab = t.$1),
                        borderRadius: BorderRadius.circular(7),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: _libraryTab == t.$1 ? AppColors.gold.withValues(alpha: 0.15) : Colors.transparent, borderRadius: BorderRadius.circular(7)),
                          child: Text(t.$2, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _libraryTab == t.$1 ? AppColors.gold : AppColors.mute)),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ),
        if (_libraryTab == "training") ...[
          if (workoutLibrary.isEmpty) const HintBox(text: "No saved templates yet. Build a program and it'll appear here too."),
          ...workoutLibrary.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _LibraryCard(
                  name: p.name,
                  onAssign: () => _writeSavedPrograms([
                    ..._record.savedPrograms,
                    SavedProgram(id: "${DateTime.now().microsecondsSinceEpoch}", name: p.name, status: "active", programDays: p.programDays, createdAt: stamp()),
                  ]),
                  onDuplicate: () async {
                    final copy = p.copyWith(name: "${p.name} (copy)");
                    try {
                      await SupabaseService.upsertProgramLibraryEntry(SavedProgram(id: "${DateTime.now().microsecondsSinceEpoch}", name: copy.name, programDays: copy.programDays));
                      ref.read(programsLibraryProvider.notifier).add(copy);
                    } catch (_) {}
                  },
                  onDelete: () async {
                    if (!await _confirm("Delete template \"${p.name}\"? This can't be undone.", confirmLabel: "Delete")) return;
                    try {
                      await SupabaseService.deleteProgramLibraryEntry(p.id);
                      ref.read(programsLibraryProvider.notifier).remove(p.id);
                    } catch (_) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't delete — check your connection and try again.")));
                    }
                  },
                ),
              )),
        ] else ...[
          if (nutritionLibrary.isEmpty) const HintBox(text: "No saved nutrition templates yet."),
          ...nutritionLibrary.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _LibraryCard(
                  name: e.name,
                  onAssign: () => SupabaseService.updateClientNutrition(widget.clientId, e.plan).then((_) {
                    ref.read(trainerClientRecordsProvider.notifier).update(widget.clientId, (r) => r.copyWith(nutrition: e.plan));
                  }).catchError((Object _) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't assign — check your connection and try again.")));
                  }),
                  onDuplicate: null,
                  onDelete: () async {
                    if (!await _confirm("Delete template \"${e.name}\"? This can't be undone.", confirmLabel: "Delete")) return;
                    ref.read(nutritionLibraryProvider.notifier).remove(e.id);
                  },
                ),
              )),
        ],
      ],
    );
  }
}

class _ProgramCard extends StatelessWidget {
  const _ProgramCard({
    required this.name,
    required this.meta,
    this.modifiedLabel,
    required this.archived,
    required this.busy,
    required this.onEdit,
    required this.onArchiveToggle,
    required this.onDuplicate,
    required this.onAssign,
    required this.onDelete,
  });

  final String name;
  final String meta;
  final String? modifiedLabel;
  final bool archived;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onArchiveToggle;
  final VoidCallback onDuplicate;
  final VoidCallback onAssign;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: archived ? 0.6 : 1,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                if (archived) const Tag(text: "Archived"),
              ],
            ),
            Padding(padding: const EdgeInsets.only(top: 2), child: Text(meta, style: const TextStyle(fontSize: 11, color: AppColors.mute))),
            if (modifiedLabel != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(modifiedLabel!, style: const TextStyle(fontSize: 11, color: AppColors.mute))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _ActionChip(label: "Edit", onTap: busy ? null : onEdit),
                _ActionChip(label: archived ? "Unarchive" : "Archive", onTap: busy ? null : onArchiveToggle),
                _ActionChip(label: "Duplicate", onTap: busy ? null : onDuplicate),
                _ActionChip(label: "Assign", onTap: busy ? null : onAssign),
                _ActionChip(label: "Delete", danger: true, onTap: busy ? null : onDelete),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryCard extends StatelessWidget {
  const _LibraryCard({required this.name, required this.onAssign, required this.onDuplicate, required this.onDelete});

  final String name;
  final VoidCallback onAssign;
  final VoidCallback? onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _ActionChip(label: "Assign", onTap: onAssign),
              if (onDuplicate != null) _ActionChip(label: "Duplicate", onTap: onDuplicate),
              _ActionChip(label: "Delete", danger: true, onTap: onDelete),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.label, required this.onTap, this.danger = false});
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFC97F7F) : AppColors.gold;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: onTap == null ? AppColors.line : color.withValues(alpha: 0.5)),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: onTap == null ? AppColors.mute : color)),
      ),
    );
  }
}
