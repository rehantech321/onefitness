import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/client_record.dart";
import "../../../data/models/intake_schema.dart";

/// Mirrors FormFiller.jsx — a generic schema-driven questionnaire renderer:
/// text/textarea/single/multi/scale question types, with `showIf`
/// conditional visibility, saving to `client.intake[key]`. Reused by both
/// the client filling their own form (`who: "client"`, from
/// IntakeAreaScreen via client_shell.dart) and a coach filling it on a
/// client's behalf (`who: "trainer"`, from IntakeTab) — [profileId]/[client]
/// identify whose record this is, and [onSaved] routes the result back into
/// whichever provider the caller owns (clientRecordProvider vs.
/// trainerClientRecordsProvider), matching FormFiller.jsx's own
/// `by: who === "client" ? "Client" : "Trainer/Coach"`.
class FormFillerScreen extends ConsumerStatefulWidget {
  const FormFillerScreen({
    super.key,
    required this.assessmentKey,
    required this.schema,
    required this.onBack,
    required this.profileId,
    required this.client,
    required this.who,
    required this.onSaved,
  });

  final String assessmentKey;
  final IntakeSchema schema;
  final VoidCallback onBack;
  final String profileId;
  final ClientRecord client;
  final String who; // "client" | "trainer"
  final void Function(IntakeRecord) onSaved;

  @override
  ConsumerState<FormFillerScreen> createState() => _FormFillerScreenState();
}

class _FormFillerScreenState extends ConsumerState<FormFillerScreen> {
  late Map<String, dynamic> _answers;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.client.intake[widget.assessmentKey];
    _answers = Map<String, dynamic>.from(existing?.answers ?? {});
  }

  void _setText(String id, dynamic v) => setState(() => _answers[id] = v);

  void _toggleMulti(String id, String opt) => setState(() {
        final cur = List<String>.from(_answers[id] as List? ?? const []);
        if (cur.contains(opt)) {
          cur.remove(opt);
        } else {
          cur.add(opt);
        }
        _answers[id] = cur;
      });

  bool _shouldShow(IntakeQuestion q) {
    if (q.showIfId == null) return true;
    final dep = _answers[q.showIfId];
    if (dep is List) return dep.contains(q.showIfValue);
    return dep == q.showIfValue;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final record = IntakeRecord(answers: _answers, completed: true, at: stamp(), by: widget.who == "client" ? "Client" : "Trainer/Coach");
    try {
      await SupabaseService.updateClientIntake(widget.profileId, widget.assessmentKey, record);
      widget.onSaved(record);
      // Nutrition Intake completing kicks off an AI-drafted calorie/macro
      // target set (training vs. rest day) — fire-and-forget exactly like
      // IntakeArea.jsx's own trigger; a coach reviews and applies it later
      // from NutritionBuilder, it's never visible to the client directly.
      // Fires whether the client or a coach completed it (JS's own trigger
      // has no `who` check either). Only checks for a prior AI draft (not
      // any nutrition program at all — most real clients already have a
      // coach-built plan on file, and that shouldn't block their first AI
      // target draft from ever generating).
      if (widget.assessmentKey == "nutritional" && !widget.client.savedNutritionPrograms.any((p) => p.source == "ai")) {
        SupabaseService.generateAiNutritionProgram(widget.profileId).catchError((_) => <String, dynamic>{});
      }
      widget.onBack();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = "Couldn't save — check your connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onBack),
          const SizedBox(height: 6),
          Text(widget.schema.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 16),
            child: Text("Fill what you can — it saves to the client's profile.", style: TextStyle(fontSize: 12, color: AppColors.mute)),
          ),
          ...widget.schema.sections.map((sec) => Padding(
                padding: const EdgeInsets.only(bottom: 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sec.title.toUpperCase(),
                      style: const TextStyle(fontSize: 11, color: AppColors.gold, fontWeight: FontWeight.w700, letterSpacing: 1),
                    ),
                    const SizedBox(height: 12),
                    ...sec.questions.where(_shouldShow).map((q) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(q.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 7),
                              _QuestionInput(
                                question: q,
                                value: _answers[q.id],
                                onText: (v) => _setText(q.id, v),
                                onToggle: (opt) => _toggleMulti(q.id, opt),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              )),
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.errorText.withValues(alpha: 0.1),
                border: Border.all(color: AppColors.errorText.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!, style: const TextStyle(color: AppColors.errorText, fontSize: 12)),
            ),
          ],
          BtnGold(
            onPressed: _saving ? null : _save,
            full: true,
            child: _saving
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                      ),
                      SizedBox(width: 8),
                      Text("Saving…"),
                    ],
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.check, size: 16, color: Colors.white),
                      SizedBox(width: 6),
                      Text("Save & mark complete"),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _QuestionInput extends StatelessWidget {
  const _QuestionInput({required this.question, required this.value, required this.onText, required this.onToggle});
  final IntakeQuestion question;
  final dynamic value;
  final ValueChanged<dynamic> onText;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    switch (question.type) {
      case "text":
        return AppField(
          placeholder: "Type here…",
          controller: TextEditingController(text: value as String? ?? "")..selection = TextSelection.collapsed(offset: (value as String? ?? "").length),
          onChanged: onText,
        );
      case "textarea":
        return TextField(
          controller: TextEditingController(text: value as String? ?? "")..selection = TextSelection.collapsed(offset: (value as String? ?? "").length),
          onChanged: onText,
          minLines: 3,
          maxLines: 6,
          style: const TextStyle(color: AppColors.txt, fontSize: 14),
          decoration: InputDecoration(
            hintText: "Type here…",
            hintStyle: const TextStyle(color: AppColors.mute),
            filled: true,
            fillColor: AppColors.bg,
            contentPadding: const EdgeInsets.all(10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.gold)),
          ),
        );
      case "scale":
        final min = question.min ?? 1;
        final max = question.max ?? 10;
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: List.generate(max - min + 1, (i) => min + i).map((n) {
            final selected = value == n;
            return InkWell(
              onTap: () => onText(n),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.bg,
                  border: Border.all(color: selected ? AppColors.gold : AppColors.line),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text("$n", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? AppColors.gold : AppColors.mute)),
              ),
            );
          }).toList(),
        );
      case "multi":
        final selected = List<String>.from(value as List? ?? const []);
        return Wrap(
          spacing: 7,
          runSpacing: 7,
          children: question.options.map((opt) {
            final on = selected.contains(opt);
            return _OptionChip(label: opt, selected: on, onTap: () => onToggle(opt));
          }).toList(),
        );
      default: // "single"
        return Wrap(
          spacing: 7,
          runSpacing: 7,
          children: question.options.map((opt) {
            final on = value == opt;
            return _OptionChip(label: opt, selected: on, onTap: () => onText(opt));
          }).toList(),
        );
    }
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.bg,
          border: Border.all(color: selected ? AppColors.gold : AppColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? AppColors.gold : AppColors.mute)),
      ),
    );
  }
}
