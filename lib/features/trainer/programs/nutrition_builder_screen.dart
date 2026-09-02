import "dart:convert";

import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/nutrition_helpers.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/nutrition_library_entry.dart";
import "../../../data/models/nutrition_plan.dart";
import "../../../data/providers/platform_settings_provider.dart";
import "../../../data/providers/trainer_providers.dart";
import "calorie_budget_panel.dart";
import "meal_picker_sheet.dart";
import "scaled_meal_card.dart";

const _mealCategories = [("breakfast", "Breakfast"), ("lunch", "Lunch"), ("dinner", "Dinner"), ("snacks", "Snacks"), ("smoothies", "Smoothies")];

String _uid() => DateTime.now().microsecondsSinceEpoch.toString();

/// Mirrors NutritionBuilder.jsx — training/rest day macro targets (with the
/// protein/carb/fat % match bar), a per-category calorie-budget panel, the
/// AI-draft generate/regenerate/apply/discard flow, the 5 meal-category
/// editors (each meal auto-scaled to its category's budget, with
/// per-ingredient override inputs), an auto-built grocery list, PDF
/// document attachments, and guidelines. When [clientId] is set, every
/// edit auto-saves to that client's real ClientRecord.nutrition, same as
/// the web's `save()` being called on every change; otherwise (drawer
/// "Build Nutrition Program") it's a template-only builder that writes
/// into the shared library on "Save nutrition program".
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
  late DaySplit<Map<String, String>> _mealBudgets = widget.existing?.mealBudgets ?? const DaySplit(training: {}, rest: {});
  late List<NutritionMeal> _breakfast = [...(widget.existing?.breakfast ?? [])];
  late List<NutritionMeal> _lunch = [...(widget.existing?.lunch ?? [])];
  late List<NutritionMeal> _dinner = [...(widget.existing?.dinner ?? [])];
  late List<NutritionMeal> _snacks = [...(widget.existing?.snacks ?? [])];
  late List<NutritionMeal> _smoothies = [...(widget.existing?.smoothies ?? [])];
  late final _guidelines = TextEditingController(text: widget.existing?.guidelines ?? "");
  late final _extraGroceryItems = TextEditingController(text: widget.existing?.extraGroceryItems ?? "");
  late List<NutritionAttachment> _attachments = [...(widget.existing?.attachments ?? [])];
  String _budgetDayType = "training";
  bool _generatingDraft = false;
  bool _regeneratingDraft = false;
  bool _saving = false;
  bool _copied = false;
  String? _error;
  String? _fileErr;

  List<NutritionMeal> _listFor(String cat) => switch (cat) {
        "breakfast" => _breakfast,
        "lunch" => _lunch,
        "dinner" => _dinner,
        "snacks" => _snacks,
        _ => _smoothies,
      };

  void _setListFor(String cat, List<NutritionMeal> list) {
    setState(() {
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
    _persist();
  }

  Future<void> _addMeal(String cat) async {
    final picked = await showMealPickerSheet(context, cat);
    if (picked == null) return;
    final dayBudget = _budgetDayType == "training" ? _mealBudgets.training : _mealBudgets.rest;
    final calTarget = int.tryParse(dayBudget[cat] ?? "");
    final scaling = scaleMeal(picked, calTarget);
    _setListFor(cat, [
      ..._listFor(cat),
      NutritionMeal(
        id: _uid(),
        name: picked.name,
        time: "",
        calories: picked.calories,
        protein: picked.protein,
        carbs: picked.carbs,
        fats: picked.fats,
        ingredients: picked.ingredients,
        instructions: picked.instructions,
        notes: picked.notes,
        isCustom: picked.isCustom,
        targetCalories: calTarget,
        scale: scaling?.scale,
        scaledIngredients: scaling?.scaledIngredients,
        scaledMacros: scaling?.scaledMacros,
      ),
    ]);
  }

  NutritionPlan _buildPlan() => NutritionPlan(
        trainingTargets: _training,
        restTargets: _rest,
        mealBudgets: _mealBudgets,
        breakfast: _breakfast,
        lunch: _lunch,
        dinner: _dinner,
        snacks: _snacks,
        smoothies: _smoothies,
        guidelines: _guidelines.text.trim().isEmpty ? null : _guidelines.text.trim(),
        extraGroceryItems: _extraGroceryItems.text.trim().isEmpty ? null : _extraGroceryItems.text.trim(),
        attachments: _attachments,
      );

  /// Mirrors NutritionBuilder.jsx's `save(n) = persist({...client, nutrition: n})`
  /// — fires on every single edit. A template build (no clientId) stays
  /// purely local until "Save nutrition program".
  void _persist() {
    final clientId = widget.clientId;
    if (clientId == null) return;
    final plan = _buildPlan();
    SupabaseService.updateClientNutrition(clientId, plan).catchError((Object _) {});
    ref.read(trainerClientRecordsProvider.notifier).update(clientId, (r) => r.copyWith(nutrition: plan));
  }

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

  Future<bool> _confirm(String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("Draft fresh targets")),
        ],
      ),
    );
    return result ?? false;
  }

  // The AI generate/regenerate edge functions write straight to
  // client_records server-side (service-role), so nothing here reflects the
  // result until real data is explicitly refetched — otherwise a successful
  // generation looks like nothing happened, and a second click reports
  // "already exists" against a draft the coach can't see yet.
  Future<void> _refreshClient() async {
    final id = widget.clientId;
    if (id == null) return;
    try {
      final fresh = await SupabaseService.loadClientRecord(id);
      ref.read(trainerClientRecordsProvider.notifier).update(id, (_) => fresh);
    } catch (_) {
      // Keep whatever's already showing on failure.
    }
  }

  Future<void> _generateNutritionDraft() async {
    setState(() => _generatingDraft = true);
    try {
      final res = await SupabaseService.generateAiNutritionProgram(widget.clientId!);
      if (res["ok"] == false) {
        _showAlert(res["reason"] == "nutrition-intake-incomplete"
            ? "The Nutrition Intake isn't marked complete yet."
            : "A draft already exists for this client.");
      }
    } catch (e) {
      _showAlert(e.toString().replaceFirst("Exception: ", ""));
    }
    await _refreshClient();
    if (mounted) setState(() => _generatingDraft = false);
  }

  Future<void> _regenerateNutritionDraft() async {
    final ok = await _confirm(
      "Draft fresh targets from this client's current Nutrition Intake answers? This creates a new draft to review — nothing on this page changes until you apply it.",
    );
    if (!ok) return;
    setState(() => _regeneratingDraft = true);
    try {
      await SupabaseService.generateAiNutritionProgram(widget.clientId!, forceRegenerate: true);
    } catch (e) {
      _showAlert(e.toString().replaceFirst("Exception: ", ""));
    }
    await _refreshClient();
    if (mounted) setState(() => _regeneratingDraft = false);
  }

  Future<void> _applyNutritionDraft(NutritionProgramEntry draft) async {
    setState(() {
      _training = draft.trainingTargets;
      _rest = draft.restTargets;
      _mealBudgets = draft.mealBudgets;
      if (draft.guidelines != null && draft.guidelines!.isNotEmpty) _guidelines.text = draft.guidelines!;
      _saving = true;
      _error = null;
    });
    try {
      final record = ref.read(trainerClientRecordsProvider)[widget.clientId];
      final nextPrograms = (record?.savedNutritionPrograms ?? const <NutritionProgramEntry>[])
          .map((p) => p.id == draft.id ? p.copyWith(status: "active") : p)
          .toList();
      await SupabaseService.updateClientNutrition(widget.clientId!, _buildPlan());
      await SupabaseService.updateClientSavedNutritionPrograms(widget.clientId!, nextPrograms);
      ref.read(trainerClientRecordsProvider.notifier).update(
            widget.clientId!,
            (r) => r.copyWith(nutrition: _buildPlan(), savedNutritionPrograms: nextPrograms),
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = "Couldn't apply this draft — check your connection and try again.");
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _discardNutritionDraft(String id) async {
    setState(() => _saving = true);
    try {
      final record = ref.read(trainerClientRecordsProvider)[widget.clientId];
      final nextPrograms = (record?.savedNutritionPrograms ?? const <NutritionProgramEntry>[]).where((p) => p.id != id).toList();
      await SupabaseService.updateClientSavedNutritionPrograms(widget.clientId!, nextPrograms);
      ref.read(trainerClientRecordsProvider.notifier).update(widget.clientId!, (r) => r.copyWith(savedNutritionPrograms: nextPrograms));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = "Couldn't discard this draft — check your connection and try again.");
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _save() async {
    final plan = _buildPlan();
    if (widget.clientId != null) {
      setState(() {
        _saving = true;
        _error = null;
      });
      try {
        await SupabaseService.updateClientNutrition(widget.clientId!, plan);
        ref.read(trainerClientRecordsProvider.notifier).update(widget.clientId!, (r) => r.copyWith(nutrition: plan));
        if (mounted) Navigator.of(context).maybePop();
      } catch (e) {
        if (!mounted) return;
        setState(() => _error = "Couldn't save — check your connection and try again.");
      }
      if (mounted) setState(() => _saving = false);
      return;
    }
    final name = await _promptName(context);
    if (name == null || name.trim().isEmpty) return;
    ref.read(nutritionLibraryProvider.notifier).add(NutritionLibraryEntry(id: _uid(), name: name.trim(), plan: plan));
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _copyGroceryList(List<GroceryCategory> categories) async {
    final text = groceryListAsText(categories, _extraGroceryItems.text);
    await Clipboard.setData(ClipboardData(text: text));
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _pickAttachment() async {
    setState(() => _fileErr = null);
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ["pdf"], withData: true);
    final file = result?.files.firstOrNull;
    if (file == null) return;
    if (file.bytes == null) {
      setState(() => _fileErr = "Couldn't read that file.");
      return;
    }
    if (file.size > 2 * 1024 * 1024) {
      setState(() => _fileErr = "That PDF is too large — please keep it under 2MB.");
      return;
    }
    final dataUrl = "data:application/pdf;base64,${base64Encode(file.bytes!)}";
    setState(() => _attachments = [..._attachments, NutritionAttachment(id: _uid(), name: file.name, dataUrl: dataUrl, size: file.size)]);
    _persist();
  }

  void _removeAttachment(String id) {
    setState(() => _attachments = _attachments.where((a) => a.id != id).toList());
    _persist();
  }

  @override
  void dispose() {
    _guidelines.dispose();
    _extraGroceryItems.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = ref.watch(trainerAuthProvider) == "owner";
    final canEdit = isOwner || ref.watch(platformSettingsProvider).coachCanEditClientWorkouts;
    if (!canEdit) {
      return const Padding(padding: EdgeInsets.all(18), child: HintBox(text: "Only the owner can build, approve, or assign nutrition programs."));
    }
    final clientId = widget.clientId;
    final record = clientId != null ? ref.watch(trainerClientRecordsProvider)[clientId] : null;
    final nutritionIntakeComplete = record?.intake["nutritional"]?.completed ?? false;
    final aiDrafts = (record?.savedNutritionPrograms ?? const <NutritionProgramEntry>[])
        .where((p) => p.source == "ai" && p.status == "draft")
        .toList();
    final hasAnyAiNutrition = (record?.savedNutritionPrograms ?? const <NutritionProgramEntry>[]).any((p) => p.source == "ai");
    final refAnswers = record?.intake["nutritional"]?.answers;
    final refItems = refAnswers == null
        ? const <(String, String)>[]
        : [
            ("Height", refAnswers["height"]),
            ("Current Weight", refAnswers["weight"]),
            ("Goal Weight", refAnswers["goalWeight"]),
            ("Goal", refAnswers["mainGoal"]),
            ("Diet", refAnswers["dietaryStyle"]),
            ("Allergies", refAnswers["allergies"]),
            ("Dislikes", refAnswers["dislikes"]),
            ("Enjoys", refAnswers["enjoy"]),
          ]
              .where((e) => e.$2 != null && (e.$2 is! List || (e.$2 as List).isNotEmpty))
              .map((e) => (e.$1, e.$2 is List ? (e.$2 as List).join(", ") : e.$2.toString()))
              .toList();

    final dayBudget = _budgetDayType == "training" ? _mealBudgets.training : _mealBudgets.rest;
    final dailyCalTarget = int.tryParse((_budgetDayType == "training" ? _training.calories : _rest.calories) ?? "") ?? 0;
    final groceryCategories = buildGroceryList(_buildPlan());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (refItems.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.06),
                border: Border.all(color: AppColors.goldDim),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("FROM THEIR ASSESSMENT", style: TextStyle(fontSize: 10, color: AppColors.gold, fontWeight: FontWeight.w700, letterSpacing: 1)),
                  const SizedBox(height: 6),
                  ...refItems.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 12, color: AppColors.mute),
                            children: [
                              TextSpan(text: "${e.$1}: ", style: const TextStyle(color: AppColors.txt, fontWeight: FontWeight.w600)),
                              TextSpan(text: e.$2),
                            ],
                          ),
                        ),
                      )),
                ],
              ),
            ),

          if (clientId != null && aiDrafts.isEmpty && nutritionIntakeComplete)
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.08),
                border: Border.all(color: AppColors.goldDim),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          hasAnyAiNutrition ? "Regenerate from their Nutrition Intake" : "Draft calorie & macro targets with AI",
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Tag(text: "AI", gold: true),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hasAnyAiNutrition
                        ? "If this client has updated their Nutrition Intake answers since their targets were last set, draft a fresh set from their current answers. You'll review it here before anything on this page changes."
                        : "This client's Nutrition Intake is complete but no AI draft has been generated yet. Draft whole-number Training/Rest Day targets, Water, Calorie Budget, and coaching notes from their intake answers — you'll review it here before anything is applied.",
                    style: const TextStyle(fontSize: 12, color: AppColors.mute, height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  if (isOwner)
                    BtnGold(
                      full: true,
                      onPressed: (_generatingDraft || _regeneratingDraft)
                          ? null
                          : (hasAnyAiNutrition ? _regenerateNutritionDraft : _generateNutritionDraft),
                      child: Text(_generatingDraft || _regeneratingDraft
                          ? "Generating…"
                          : hasAnyAiNutrition
                              ? "Regenerate AI Nutrition Targets"
                              : "Generate AI Nutrition Targets"),
                    )
                  else
                    const Text("Only the owner can generate AI drafts.", style: TextStyle(fontSize: 12, color: AppColors.mute, fontStyle: FontStyle.italic)),
                ],
              ),
            ),

          for (final p in aiDrafts)
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.08),
                border: Border.all(color: AppColors.goldDim),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Expanded(child: Text("AI-drafted calorie & macro targets are ready", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                      SizedBox(width: 6),
                      Tag(text: "AI Draft", gold: true),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Training: ${p.trainingTargets.calories ?? "—"} kcal · ${p.trainingTargets.protein ?? "—"}/${p.trainingTargets.carbs ?? "—"}/${p.trainingTargets.fats ?? "—"}% P/C/F",
                    style: const TextStyle(fontSize: 12, color: AppColors.mute),
                  ),
                  Text(
                    "Rest: ${p.restTargets.calories ?? "—"} kcal · ${p.restTargets.protein ?? "—"}/${p.restTargets.carbs ?? "—"}/${p.restTargets.fats ?? "—"}% P/C/F",
                    style: const TextStyle(fontSize: 12, color: AppColors.mute),
                  ),
                  if (p.mealBudgets.training.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        "Training budget: ${p.mealBudgets.training["breakfast"] ?? "—"}/${p.mealBudgets.training["lunch"] ?? "—"}/${p.mealBudgets.training["dinner"] ?? "—"}/${p.mealBudgets.training["snacks"] ?? "—"} kcal (B/L/D/S)",
                        style: const TextStyle(fontSize: 12, color: AppColors.mute),
                      ),
                    ),
                  if (p.guidelines != null && p.guidelines!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('"${p.guidelines}"', style: const TextStyle(fontSize: 12, color: AppColors.mute, fontStyle: FontStyle.italic)),
                    ),
                  const SizedBox(height: 8),
                  const HintBox(text: "Applying fills in the Training/Rest Day Targets, Water, Calorie Budget, and Guidelines & Notes below with this draft — your meals and grocery list are untouched. Review it first if you'd like to adjust anything."),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: BtnGold(onPressed: _saving ? null : () => _applyNutritionDraft(p), child: const Text("Apply to this plan")),
                      ),
                      if (isOwner) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: BtnGhost(
                            onPressed: _regeneratingDraft ? null : _regenerateNutritionDraft,
                            child: Text(_regeneratingDraft ? "Regenerating…" : "Regenerate"),
                          ),
                        ),
                      ],
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving ? null : () => _discardNutritionDraft(p.id),
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF6B3B3B)), foregroundColor: const Color(0xFFC97F7F)),
                          child: const Text("Discard"),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: AppColors.errorText, fontSize: 12)),
            const SizedBox(height: 10),
          ],

          const SectionLabel("Training Day Targets"),
          _TargetsCard(targets: _training, onChange: (t) {
            setState(() => _training = t);
            _persist();
          }),
          const SizedBox(height: 4),
          const SectionLabel("Rest Day Targets"),
          _TargetsCard(targets: _rest, onChange: (t) {
            setState(() => _rest = t);
            _persist();
          }),

          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(3),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.line)),
            child: Row(
              children: [
                Expanded(child: _DayTypeTab(label: "Training Day", selected: _budgetDayType == "training", onTap: () => setState(() => _budgetDayType = "training"))),
                Expanded(child: _DayTypeTab(label: "Rest Day", selected: _budgetDayType == "rest", onTap: () => setState(() => _budgetDayType = "rest"))),
              ],
            ),
          ),
          CalorieBudgetPanel(
            mealBudgets: dayBudget,
            dailyCalTarget: dailyCalTarget,
            onChange: (mb) {
              setState(() => _mealBudgets = _budgetDayType == "training" ? _mealBudgets.copyWith(training: mb) : _mealBudgets.copyWith(rest: mb));
              _persist();
            },
          ),

          for (final cat in _mealCategories) ...[
            const SizedBox(height: 20),
            SectionLabel("${cat.$2}${(int.tryParse(dayBudget[cat.$1] ?? "") ?? 0) > 0 ? " — ${dayBudget[cat.$1]} kcal target" : ""}"),
            if (_listFor(cat.$1).isEmpty) const HintBox(text: "None yet."),
            ..._listFor(cat.$1).asMap().entries.map((entry) => ScaledMealCard(
                  meal: entry.value,
                  onRemove: () => _setListFor(cat.$1, [..._listFor(cat.$1)]..removeAt(entry.key)),
                  onUpdate: (m) => _setListFor(cat.$1, [for (final e in _listFor(cat.$1)) e.id == m.id ? m : e]),
                )),
            BtnGold(full: true, onPressed: () => _addMeal(cat.$1), child: Text("+ Add ${cat.$2.toLowerCase()}")),
          ],

          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionLabel("Grocery List"),
              if (groceryCategories.isNotEmpty)
                OutlinedButton(
                  onPressed: () => _copyGroceryList(groceryCategories),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.gold, side: const BorderSide(color: AppColors.line), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5)),
                  child: Text(_copied ? "Copied!" : "Copy list", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          if (groceryCategories.isEmpty)
            const HintBox(text: "Add meals above and the grocery list builds itself — combined, deduplicated, and organized by category.")
          else
            ...groceryCategories.map((cat) => AppCard(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cat.label.toUpperCase(), style: const TextStyle(fontSize: 10, color: AppColors.gold, fontWeight: FontWeight.w700, letterSpacing: 1)),
                      const SizedBox(height: 8),
                      ...cat.items.asMap().entries.map((entry) => Container(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            decoration: entry.key < cat.items.length - 1 ? const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))) : null,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(entry.value.item, style: const TextStyle(fontSize: 13, color: AppColors.txt)),
                                Text("${fmtQty(entry.value.qty)} ${entry.value.unit ?? ""}".trim(), style: const TextStyle(fontSize: 13, color: AppColors.mute)),
                              ],
                            ),
                          )),
                    ],
                  ),
                )),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: AppField(
              controller: _extraGroceryItems,
              placeholder: "Additional items not covered above (optional) — e.g. protein powder, vitamins",
              onChanged: (_) => _persist(),
            ),
          ),

          const SizedBox(height: 20),
          const SectionLabel("Documents"),
          if (_attachments.isEmpty) const HintBox(text: "No documents yet."),
          ..._attachments.map((doc) => AppCard(
                margin: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(LucideIcons.fileText, size: 18, color: AppColors.gold),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(doc.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          Text("${(doc.size / 1024).toStringAsFixed(0)} KB", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                        ],
                      ),
                    ),
                    IconButton(onPressed: () => _removeAttachment(doc.id), icon: const Icon(LucideIcons.trash2, size: 14, color: Color(0xFF6B3B3B))),
                  ],
                ),
              )),
          InkWell(
            onTap: _pickAttachment,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(border: Border.all(color: AppColors.goldDim), borderRadius: BorderRadius.circular(10)),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [Icon(LucideIcons.plus, size: 15, color: AppColors.gold), SizedBox(width: 6), Text("Upload PDF", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.gold))],
              ),
            ),
          ),
          if (_fileErr != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_fileErr!, style: const TextStyle(color: Color(0xFFC97F7F), fontSize: 12))),

          const SizedBox(height: 20),
          const SectionLabel("Guidelines & Notes"),
          TextField(
            controller: _guidelines,
            maxLines: 4,
            style: const TextStyle(color: AppColors.txt, fontSize: 13),
            onChanged: (_) => _persist(),
            decoration: InputDecoration(
              hintText: "Hydration, supplements, dos & don'ts, coaching notes…",
              hintStyle: const TextStyle(color: AppColors.mute),
              filled: true,
              fillColor: AppColors.card,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.gold)),
            ),
          ),
          const SizedBox(height: 12),
          BtnGhost(
            full: true,
            onPressed: _saving ? null : _save,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [const Icon(LucideIcons.save, size: 14), const SizedBox(width: 7), Text(_saving ? "Saving…" : "Save nutrition program")],
            ),
          ),
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

class _DayTypeTab extends StatelessWidget {
  const _DayTypeTab({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: selected ? AppColors.gold : Colors.transparent, borderRadius: BorderRadius.circular(6)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? Colors.white : AppColors.mute)),
      ),
    );
  }
}

class _TargetsCard extends StatelessWidget {
  const _TargetsCard({required this.targets, required this.onChange});
  final MacroTargets targets;
  final ValueChanged<MacroTargets> onChange;

  @override
  Widget build(BuildContext context) {
    final p = double.tryParse(targets.protein ?? "") ?? 0;
    final c = double.tryParse(targets.carbs ?? "") ?? 0;
    final f = double.tryParse(targets.fats ?? "") ?? 0;
    final total = p + c + f;
    final ok = total == 100;

    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: MiniField(label: "Calories (kcal)", value: targets.calories ?? "", onChange: (v) => onChange(MacroTargets(calories: v, protein: targets.protein, carbs: targets.carbs, fats: targets.fats, water: targets.water)))),
              const SizedBox(width: 6),
              Expanded(child: MiniField(label: "Protein % (%)", value: targets.protein ?? "", onChange: (v) => onChange(MacroTargets(calories: targets.calories, protein: v, carbs: targets.carbs, fats: targets.fats, water: targets.water)))),
              const SizedBox(width: 6),
              Expanded(child: MiniField(label: "Carbs % (%)", value: targets.carbs ?? "", onChange: (v) => onChange(MacroTargets(calories: targets.calories, protein: targets.protein, carbs: v, fats: targets.fats, water: targets.water)))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: MiniField(label: "Fat % (%)", value: targets.fats ?? "", onChange: (v) => onChange(MacroTargets(calories: targets.calories, protein: targets.protein, carbs: targets.carbs, fats: v, water: targets.water)))),
              const SizedBox(width: 6),
              Expanded(child: MiniField(label: "Water", value: targets.water ?? "", onChange: (v) => onChange(MacroTargets(calories: targets.calories, protein: targets.protein, carbs: targets.carbs, fats: targets.fats, water: v)))),
              const SizedBox(width: 6),
              const Expanded(child: SizedBox()),
            ],
          ),
          if (total > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: SizedBox(
                        height: 5,
                        child: Row(
                          children: [
                            for (final seg in [(p, AppColors.grn), (c, AppColors.gold), (f, const Color(0xFFD68A4F)), (100 - total, AppColors.line)])
                              if (seg.$1 > 0) Expanded(flex: seg.$1.round().clamp(1, 1000), child: Container(color: seg.$2)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "${total.round()}%${ok ? " ✓" : ""}",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ok ? AppColors.grn : const Color(0xFFC97F7F)),
                  ),
                ],
              ),
            ),
          if (total > 0 && !ok)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Align(alignment: Alignment.centerRight, child: Text("← should equal 100%", style: TextStyle(fontSize: 10, color: Color(0xFFC97F7F)))),
            ),
        ],
      ),
    );
  }
}
