import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/intake_schema.dart";
import "intake_attachments.dart";

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
class IntakeAnswersScreen extends StatefulWidget {
  const IntakeAnswersScreen({
    super.key,
    required this.schema,
    required this.record,
    required this.profileId,
    required this.assessmentKey,
    required this.onBack,
    required this.onEdit,
    this.onFillAgain,
    this.schemaFor,
  });

  final IntakeSchema schema;
  final IntakeRecord record;

  /// Whose record this is, and which form — needed to open the attachments,
  /// which live in storage rather than in the record itself.
  final String profileId;
  final String assessmentKey;

  final VoidCallback onBack;

  /// Correct what's on record — same submission, fixed.
  final VoidCallback onEdit;

  /// Answer the whole questionnaire again, keeping the current answers as an
  /// earlier submission. Null hides the option, which is what the client's
  /// own view wants: re-filling is a coach's call.
  final VoidCallback? onFillAgain;

  /// The questions as they stood for a given form version.
  ///
  /// A gym-defined form can be revised, and a submission given against
  /// version 1 must go on being read against version 1's questions — a
  /// renamed question would otherwise relabel an old answer, and a deleted
  /// one would make it disappear. Null, or a version that can't be found,
  /// falls back to [schema].
  final IntakeSchema Function(int? version)? schemaFor;

  @override
  State<IntakeAnswersScreen> createState() => _IntakeAnswersScreenState();
}

class _IntakeAnswersScreenState extends State<IntakeAnswersScreen> {
  /// 0 is the current submission; 1 and up index [IntakeRecord.history].
  int _viewing = 0;

  bool get _isCurrent => _viewing == 0;

  /// The form version the submission on screen was filled against.
  int? get _version => _isCurrent
      ? widget.record.templateVersion
      : widget.record.history[_viewing - 1].templateVersion;

  /// The questions that submission was actually asked.
  IntakeSchema get _schema =>
      widget.schemaFor?.call(_version) ?? widget.schema;

  Map<String, dynamic> get _answers =>
      _isCurrent ? widget.record.answers : widget.record.history[_viewing - 1].answers;

  List<IntakeAttachment> get _attachments => _isCurrent
      ? widget.record.attachments
      : widget.record.history[_viewing - 1].attachments;

  String? get _at =>
      _isCurrent ? widget.record.at : widget.record.history[_viewing - 1].at;

  String? get _by =>
      _isCurrent ? widget.record.by : widget.record.history[_viewing - 1].by;

  @override
  Widget build(BuildContext context) {
    final schema = _schema;
    final record = widget.record;
    final answers = _answers;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onBack),
          const SizedBox(height: 6),
          Text(
            schema.title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            child: Row(
              children: [
                Icon(
                  _isCurrent ? LucideIcons.check : LucideIcons.history,
                  size: 14,
                  color: _isCurrent ? AppColors.gold : AppColors.mute,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "Completed by ${_by ?? "Client"}"
                    "${_at != null ? " · $_at" : ""}",
                    style: TextStyle(
                      fontSize: 12,
                      color: _isCurrent ? AppColors.gold : AppColors.mute,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (record.history.isNotEmpty) ...[
            _SubmissionPicker(
              record: record,
              viewing: _viewing,
              onPick: (i) => setState(() => _viewing = i),
            ),
            const SizedBox(height: 16),
          ],
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
                    style: TextStyle(
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
          if (_attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: IntakeAttachmentsField(
                profileId: widget.profileId,
                assessmentKey: widget.assessmentKey,
                attachments: _attachments,
                readOnly: true,
                // Read-only, so nothing here can change the list.
                onChanged: (_) {},
              ),
            ),
          // Editing only ever applies to the submission in force. A past one
          // is a record of what was said at the time — there is nothing
          // sensible to write back to, and offering Edit here would imply you
          // could rewrite history.
          if (_isCurrent) ...[
            HintBox(
              text: widget.onFillAgain == null
                  ? "Editing this re-files the form under your name and today's "
                      "date, replacing the record of who filled it in and when."
                  : "Editing corrects what's on record. Add another starts a "
                      "blank copy of this form for this client — these answers "
                      "are saved automatically and stay readable.",
            ),
            const SizedBox(height: 10),
            BtnGhost(
              onPressed: widget.onEdit,
              full: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.pencil, size: 15, color: AppColors.mute),
                  SizedBox(width: 7),
                  Text("Edit answers"),
                ],
              ),
            ),
            if (widget.onFillAgain != null) ...[
              const SizedBox(height: 8),
              BtnGhost(
                onPressed: widget.onFillAgain,
                full: true,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.filePlus, size: 15, color: AppColors.mute),
                    const SizedBox(width: 7),
                    const Text("Add another"),
                  ],
                ),
              ),
            ],
          ] else ...[
            HintBox(
              text:
                  "This is an earlier submission, kept as it was filled in. "
                  "The current answers are under ${record.at ?? "the latest entry"}.",
            ),
            const SizedBox(height: 10),
            BtnGhost(
              onPressed: () => setState(() => _viewing = 0),
              full: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.cornerUpLeft, size: 15, color: AppColors.mute),
                  const SizedBox(width: 7),
                  // Kept short: the full "Back to current answers" overflows
                  // this button on a narrow phone.
                  const Text("Back to current"),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Which submission of this form you're reading.
///
/// Only appears once a form has been filled more than once, so a client with
/// a single intake sees exactly what they saw before.
class _SubmissionPicker extends StatelessWidget {
  const _SubmissionPicker({
    required this.record,
    required this.viewing,
    required this.onPick,
  });

  final IntakeRecord record;
  final int viewing;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    // Current first, then each superseded one, newest to oldest — the order
    // they're stored in.
    final labels = <String>[
      record.at ?? "Current",
      for (final h in record.history) h.at ?? "Earlier",
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel("Submissions"),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Padding(
                  padding: EdgeInsets.only(right: i == labels.length - 1 ? 0 : 8),
                  child: _SubmissionChip(
                    label: labels[i],
                    // Saying which one is live matters more than the date: a
                    // coach scanning this needs to know what they're acting on.
                    sub: i == 0 ? "Current" : "Replaced",
                    selected: i == viewing,
                    onTap: () => onPick(i),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SubmissionChip extends StatelessWidget {
  const _SubmissionChip({
    required this.label,
    required this.sub,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.gold.withValues(alpha: 0.12) : AppColors.card,
          border: Border.all(color: selected ? AppColors.gold : AppColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.gold : AppColors.txt,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              style: TextStyle(
                fontSize: 10.5,
                color: selected ? AppColors.gold : AppColors.mute,
              ),
            ),
          ],
        ),
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
