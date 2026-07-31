import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_icons/lucide_icons.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/intake_schema.dart";
import "../../../data/providers/client_providers.dart";

/// Mirrors FormFiller.jsx — a generic schema-driven questionnaire renderer:
/// text/textarea/single/multi/scale question types, with `showIf`
/// conditional visibility, saving to `client.intake[key]`.
class FormFillerScreen extends ConsumerStatefulWidget {
  const FormFillerScreen({super.key, required this.assessmentKey, required this.schema, required this.onBack});

  final String assessmentKey;
  final IntakeSchema schema;
  final VoidCallback onBack;

  @override
  ConsumerState<FormFillerScreen> createState() => _FormFillerScreenState();
}

class _FormFillerScreenState extends ConsumerState<FormFillerScreen> {
  late Map<String, dynamic> _answers;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(clientRecordProvider).intake[widget.assessmentKey];
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

  void _save() {
    ref.read(clientRecordProvider.notifier).update((r) => r.copyWith(intake: {
          ...r.intake,
          widget.assessmentKey: IntakeRecord(answers: _answers, completed: true, at: stamp(), by: "Client"),
        }));
    widget.onBack();
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
            child: Text("Fill what you can — it saves to your profile.", style: TextStyle(fontSize: 12, color: AppColors.mute)),
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
          BtnGold(
            onPressed: _save,
            full: true,
            child: const Row(
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
