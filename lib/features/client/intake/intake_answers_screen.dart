import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/intake_schema.dart";

/// A client's completed intake, laid out for reading rather than filling in.
///
/// Staff reach every assessment through the same screens the client uses, and
/// those screens are editable forms. That is right when a coach is recording
/// answers for someone mid-signup, and wrong the rest of the time: the far
/// more common reason to open an intake is to read what the client already
/// said before a session. FormFillerScreen has one button, "Save & mark
/// complete", and pressing it rewrites the record's `by` to "Trainer/Coach"
/// and `at` to today — so a coach who opened a client's answers to read them,
/// brushed a chip and saved would quietly destroy the evidence that the
/// client filled their own form, and the date they filled it.
///
/// This screen is the default landing place for staff on a completed intake.
/// Editing is still one tap away, but it is now a decision rather than the
/// only thing on offer.
class IntakeAnswersScreen extends StatelessWidget {
  const IntakeAnswersScreen({
    super.key,
    required this.schema,
    required this.record,
    required this.onBack,
    required this.onEdit,
  });

  final IntakeSchema schema;
  final IntakeRecord record;
  final VoidCallback onBack;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final answers = record.answers;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: onBack),
          const SizedBox(height: 6),
          Text(
            schema.title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            child: Row(
              children: [
                const Icon(LucideIcons.check, size: 14, color: AppColors.gold),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "Completed by ${record.by ?? "Client"}"
                    "${record.at != null ? " · ${record.at}" : ""}",
                    style: const TextStyle(fontSize: 12, color: AppColors.gold),
                  ),
                ),
              ],
            ),
          ),
          ...schema.sections.map((sec) {
            final visible =
                sec.questions.where((q) => intakeQuestionVisible(q, answers)).toList();
            if (visible.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sec.title.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.gold,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...visible.map((q) => _AnswerRow(question: q, value: answers[q.id])),
                ],
              ),
            );
          }),
          const HintBox(
            text:
                "Editing this re-files the form under your name and today's date, "
                "replacing the record of who filled it in and when.",
          ),
          const SizedBox(height: 10),
          BtnGhost(
            onPressed: onEdit,
            full: true,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.pencil, size: 15, color: AppColors.mute),
                SizedBox(width: 7),
                Text("Edit answers"),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One question and what was answered. Questions the client skipped are kept
/// in the list rather than dropped — "they didn't say" is information a coach
/// wants before a session, and a silently shortened form would read as if
/// every question had been answered.
class _AnswerRow extends StatelessWidget {
  const _AnswerRow({required this.question, required this.value});

  final IntakeQuestion question;
  final dynamic value;

  /// The saved answer as text, or null when nothing was recorded. Scale
  /// answers carry their own scale ("7 / 10") since the number alone says
  /// nothing about how high it could have gone.
  String? get _text {
    final v = value;
    if (v == null) return null;
    if (v is List) {
      final picked = v.map((e) => "$e".trim()).where((e) => e.isNotEmpty).toList();
      return picked.isEmpty ? null : picked.join(", ");
    }
    if (v is num) return question.type == "scale" ? "$v / ${question.max ?? 10}" : "$v";
    final s = "$v".trim();
    return s.isEmpty ? null : s;
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.bg,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              text ?? "Not answered",
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: text == null ? AppColors.mute : AppColors.txt,
                fontStyle: text == null ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
