import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/write_failure.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/intake_form_template.dart";
import "../../../data/models/intake_schema.dart";
import "../../../data/providers/trainer_providers.dart";

/// The gym's own intake forms — create one, retire one, revise one.
///
/// Sits beside Waivers & Contracts because it follows the same rule for the
/// same reason: a document a client has already answered is never destroyed.
/// A waiver that has been signed can only be archived; an intake form that
/// has been answered can only be archived or superseded by a new version.
/// What a client was asked, and what they said, stays readable.
///
/// Owner-only. An intake form is the gym's questionnaire — the AI program
/// drafter reads it and the waiver's merge tokens pull from it — so one coach
/// reshaping what every client is asked is not something to allow.
class ManageIntakeFormsScreen extends ConsumerStatefulWidget {
  const ManageIntakeFormsScreen({super.key});

  @override
  ConsumerState<ManageIntakeFormsScreen> createState() =>
      _ManageIntakeFormsScreenState();
}

class _ManageIntakeFormsScreenState
    extends ConsumerState<ManageIntakeFormsScreen> {
  /// The form being written, or null when looking at the list.
  _Draft? _draft;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    // The draft owns a controller per field, and leaving the screen mid-edit
    // is the ordinary way out of it.
    _draft?.dispose();
    super.dispose();
  }

  /// Leaves the editor, releasing the draft's controllers.
  void _discardDraft() {
    _draft?.dispose();
    setState(() {
      _draft = null;
      _error = null;
    });
  }

  /// Current version of each gym form, archived ones included — the list
  /// shows retired forms too, greyed, so they can be brought back.
  List<IntakeFormTemplate> get _forms {
    final all = ref.watch(intakeFormTemplatesProvider);
    final newest = <String, IntakeFormTemplate>{};
    for (final t in all) {
      final seen = newest[t.key];
      if (seen == null || t.version > seen.version) newest[t.key] = t;
    }
    final list = newest.values.toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return list;
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null || _saving) return;

    final problem = draft.firstProblem();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await SupabaseService.saveIntakeFormTemplate(draft.build());
      ref.read(intakeFormTemplatesProvider.notifier).addVersion(saved);
      if (!mounted) return;
      setState(() => _saving = false);
      _discardDraft();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst("Exception: ", "");
      });
    }
  }

  Future<void> _toggleArchived(IntakeFormTemplate t) async {
    final next = !t.archived;
    if (next) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          title: Text('Retire "${t.title}"?'),
          content: const Text(
            "It stops being offered for new submissions. Everything clients "
            "have already answered stays saved and readable, and you can bring "
            "the form back at any time.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text("Retire"),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await SupabaseService.setIntakeFormArchived(t.key, next);
      ref.read(intakeFormTemplatesProvider.notifier).setArchived(t.key, next);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(writeFailureMessage(e, whatFailed: "Couldn't update the form"))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_draft != null) {
      return LocalBackScope(
        isOpen: true,
        onBack: _discardDraft,
        child: _FormEditor(
          draft: _draft!,
          saving: _saving,
          error: _error,
          onChanged: () => setState(() {}),
          onCancel: _discardDraft,
          onSave: _save,
        ),
      );
    }

    final forms = _forms;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Intake Forms",
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            child: Text(
              "Questionnaires your clients fill in, alongside the ones built "
              "into the app.",
              style: TextStyle(fontSize: 12, color: AppColors.mute),
            ),
          ),
          BtnGold(
            onPressed: () => setState(() {
              _draft?.dispose();
              _draft = _Draft.blank();
              _error = null;
            }),
            full: true,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.plus, size: 15),
                SizedBox(width: 6),
                Text("New form"),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (forms.isEmpty)
            const HintBox(
              text:
                  "No forms of your own yet. The built-in Training, Nutrition "
                  "and Physical Assessment forms are always available and "
                  "aren't listed here.",
            )
          else
            ...forms.map(
              (t) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _FormRow(
                  template: t,
                  onRevise: () => setState(() {
                    _draft?.dispose();
                    _draft = _Draft.from(t);
                    _error = null;
                  }),
                  onToggleArchived: () => _toggleArchived(t),
                ),
              ),
            ),
          const SizedBox(height: 8),
          const HintBox(
            text:
                "Revising a form saves it as a new version. Answers already on "
                "file keep the version they were given against, so what a "
                "client was actually asked never changes after the fact.",
          ),
        ],
      ),
    );
  }
}

class _FormRow extends StatelessWidget {
  const _FormRow({
    required this.template,
    required this.onRevise,
    required this.onToggleArchived,
  });

  final IntakeFormTemplate template;
  final VoidCallback onRevise;
  final VoidCallback onToggleArchived;

  @override
  Widget build(BuildContext context) {
    final questions =
        template.sections.fold<int>(0, (n, s) => n + s.questions.length);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  template.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: template.archived ? AppColors.mute : AppColors.txt,
                  ),
                ),
              ),
              if (template.archived)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    "Retired",
                    style: TextStyle(fontSize: 10, color: AppColors.mute),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              "${template.sections.length} section${template.sections.length == 1 ? "" : "s"}"
              " · $questions question${questions == 1 ? "" : "s"}"
              " · version ${template.version}",
              style: TextStyle(fontSize: 11, color: AppColors.mute),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: BtnGhost(
                  onPressed: onRevise,
                  full: true,
                  child: const Text("Revise"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: BtnGhost(
                  onPressed: onToggleArchived,
                  full: true,
                  child: Text(template.archived ? "Bring back" : "Retire"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


// ── The editor ────────────────────────────────────────────────────────────

/// A form being written. Mutable counterpart to [IntakeFormTemplate], which
/// is immutable once saved.
///
/// Holds its own [TextEditingController]s rather than mirroring text into
/// fields on every keystroke: the editor is a tree of nested lists, and
/// rebuilding all of it per character is both wasteful and a reliable way to
/// lose a cursor position mid-word.
class _Draft {
  _Draft({
    required this.key,
    required String title,
    required this.sections,
    required this.isNew,
    this.allowsAttachments = true,
    this.clientCanFill = true,
  }) : titleCtrl = TextEditingController(text: title);

  factory _Draft.blank() => _Draft(
    key: "",
    title: "",
    sections: [_SectionDraft(title: "", questions: [_QuestionDraft()])],
    isNew: true,
  );

  factory _Draft.from(IntakeFormTemplate t) => _Draft(
    key: t.key,
    title: t.title,
    sections: [
      for (final s in t.sections)
        _SectionDraft(
          title: s.title,
          questions: [
            for (final q in s.questions)
              _QuestionDraft(id: q.id, label: q.label, type: q.type, options: q.options),
          ],
        ),
    ],
    isNew: false,
    allowsAttachments: t.allowsAttachments,
    clientCanFill: t.clientCanFill,
  );

  /// Empty until the first save of a new form, then fixed forever: the key is
  /// what every answer already given is filed under, so a revision must keep
  /// it or those answers would no longer belong to this form.
  final String key;
  final TextEditingController titleCtrl;
  final List<_SectionDraft> sections;
  final bool isNew;
  bool allowsAttachments;
  bool clientCanFill;

  String get title => titleCtrl.text;

  void dispose() {
    titleCtrl.dispose();
    for (final s in sections) {
      s.dispose();
    }
  }

  /// The first thing wrong with this draft, or null if it's ready to save.
  String? firstProblem() {
    if (title.trim().isEmpty) return "Give the form a name.";
    if (sections.isEmpty) return "Add at least one section.";
    for (final s in sections) {
      if (s.questions.isEmpty) {
        final name = s.title.trim().isEmpty ? "Untitled" : s.title.trim();
        return 'Section "$name" has no questions.';
      }
      for (final q in s.questions) {
        if (q.label.trim().isEmpty) return "Every question needs a label.";
        if (q.wantsOptions && q.filledOptions.isEmpty) {
          return '"${q.label.trim()}" is a choice question, so it needs at least one option.';
        }
      }
    }
    return null;
  }

  IntakeFormTemplate build() {
    // Ids are generated rather than typed: they key the stored answers, so
    // they must be stable and unique, and an admin shouldn't have to care.
    // A question that already exists keeps the id it had — regenerating one
    // from a reworded label would orphan every answer given to it.
    final used = <String>{};
    final sectionsOut = <IntakeSection>[];
    for (final s in sections) {
      final questions = <IntakeQuestion>[];
      for (final q in s.questions) {
        final id = q.id ?? uniqueId(slugify(q.label), used);
        used.add(id);
        questions.add(
          IntakeQuestion(
            id: id,
            label: q.label.trim(),
            type: q.type,
            options: q.wantsOptions ? q.filledOptions : const [],
            min: q.type == "scale" ? 1 : null,
            max: q.type == "scale" ? 10 : null,
          ),
        );
      }
      sectionsOut.add(
        IntakeSection(
          title: s.title.trim().isEmpty ? "Questions" : s.title.trim(),
          questions: questions,
        ),
      );
    }

    return IntakeFormTemplate(
      key: key.isEmpty ? slugify(title) : key,
      // Overwritten by the service, which computes it from the table.
      version: 1,
      title: title.trim(),
      sections: sectionsOut,
      allowsAttachments: allowsAttachments,
      clientCanFill: clientCanFill,
    );
  }
}

/// A label turned into the identifier its answers are stored under.
///
/// Matches migration 37's `intake_form_templates_key_shape`: opens with a
/// letter, then letters, digits and underscores. Visible for testing because
/// a change here that produced a different id for the same label would file
/// new answers somewhere the old ones aren't.
String slugify(String label) {
  final buf = StringBuffer();
  for (final ch in label.trim().toLowerCase().split("")) {
    if (RegExp(r"[a-z0-9]").hasMatch(ch)) {
      buf.write(ch);
    } else if (buf.isNotEmpty && !buf.toString().endsWith("_")) {
      buf.write("_");
    }
  }
  var s = buf.toString().replaceAll(RegExp(r"_+$"), "");
  // Must open with a letter: "5k time" would otherwise start with a digit,
  // and a wholly non-alphanumeric label would come out empty.
  if (s.isEmpty || !RegExp(r"^[a-z]").hasMatch(s)) s = "q$s";
  return s.length > 40 ? s.substring(0, 40) : s;
}

/// [base], or [base] with a number appended until it isn't already taken.
String uniqueId(String base, Set<String> used) {
  if (!used.contains(base)) return base;
  for (var i = 2;; i++) {
    final candidate = "${base}_$i";
    if (!used.contains(candidate)) return candidate;
  }
}

class _SectionDraft {
  _SectionDraft({required String title, required this.questions})
      : titleCtrl = TextEditingController(text: title);

  final TextEditingController titleCtrl;
  final List<_QuestionDraft> questions;

  String get title => titleCtrl.text;

  void dispose() {
    titleCtrl.dispose();
    for (final q in questions) {
      q.dispose();
    }
  }
}

class _QuestionDraft {
  _QuestionDraft({
    this.id,
    String label = "",
    this.type = "text",
    List<String> options = const [],
  })  : labelCtrl = TextEditingController(text: label),
        optionCtrls = [
          for (final o in options) TextEditingController(text: o),
          if (options.isEmpty) TextEditingController(),
        ];

  /// Null for a question being added now; set for one that already exists, so
  /// a revision keeps the id its answers are filed under.
  final String? id;
  final TextEditingController labelCtrl;
  final List<TextEditingController> optionCtrls;
  String type;

  String get label => labelCtrl.text;
  bool get wantsOptions => type == "single" || type == "multi";
  List<String> get filledOptions => [
    for (final c in optionCtrls)
      if (c.text.trim().isNotEmpty) c.text.trim(),
  ];

  void dispose() {
    labelCtrl.dispose();
    for (final c in optionCtrls) {
      c.dispose();
    }
  }
}

const _kTypeLabels = {
  "text": "Short text",
  "textarea": "Long text",
  "single": "Choose one",
  "multi": "Choose several",
  "scale": "Scale of 1-10",
};

class _FormEditor extends StatelessWidget {
  const _FormEditor({
    required this.draft,
    required this.saving,
    required this.error,
    required this.onChanged,
    required this.onCancel,
    required this.onSave,
  });

  final _Draft draft;
  final bool saving;
  final String? error;

  /// Called for structural edits only — adding a section, removing a
  /// question, switching a type. Typing doesn't go through here.
  final VoidCallback onChanged;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: onCancel),
          const SizedBox(height: 6),
          Text(
            draft.isNew ? "New intake form" : "Revise form",
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          if (!draft.isNew)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: HintBox(
                text:
                    "Saving writes a new version. Clients who already answered "
                    "keep the version they were given, so their answers go on "
                    "reading back against the questions they actually saw.",
              ),
            ),
          const SizedBox(height: 14),
          FieldLabeled(
            label: "Form name",
            child: AppField(
              controller: draft.titleCtrl,
              placeholder: "e.g. Supplement Questionnaire",
            ),
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < draft.sections.length; i++)
            _SectionEditor(
              key: ObjectKey(draft.sections[i]),
              section: draft.sections[i],
              index: i,
              canRemove: draft.sections.length > 1,
              onChanged: onChanged,
              onRemove: () {
                draft.sections.removeAt(i).dispose();
                onChanged();
              },
            ),
          BtnGhost(
            onPressed: () {
              draft.sections.add(
                _SectionDraft(title: "", questions: [_QuestionDraft()]),
              );
              onChanged();
            },
            full: true,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.plus, size: 14),
                SizedBox(width: 6),
                Text("Add section"),
              ],
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error!,
                style: TextStyle(fontSize: 12, color: AppColors.errorText),
              ),
            ),
          const SizedBox(height: 16),
          BtnGold(
            onPressed: saving ? null : onSave,
            full: true,
            child: Text(saving ? "Saving..." : "Save form"),
          ),
        ],
      ),
    );
  }
}

class _SectionEditor extends StatelessWidget {
  const _SectionEditor({
    super.key,
    required this.section,
    required this.index,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final _SectionDraft section;
  final int index;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: SectionLabel("Section ${index + 1}")),
                if (canRemove)
                  InkWell(
                    onTap: onRemove,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(LucideIcons.trash2, size: 15, color: AppColors.mute),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            AppField(
              controller: section.titleCtrl,
              placeholder: "Section heading (optional)",
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < section.questions.length; i++)
              _QuestionEditor(
                key: ObjectKey(section.questions[i]),
                question: section.questions[i],
                canRemove: section.questions.length > 1,
                onChanged: onChanged,
                onRemove: () {
                  section.questions.removeAt(i).dispose();
                  onChanged();
                },
              ),
            BtnGhost(
              onPressed: () {
                section.questions.add(_QuestionDraft());
                onChanged();
              },
              full: true,
              child: const Text("Add question"),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionEditor extends StatelessWidget {
  const _QuestionEditor({
    super.key,
    required this.question,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final _QuestionDraft question;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.bg,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: AppField(
                    controller: question.labelCtrl,
                    placeholder: "Question",
                  ),
                ),
                if (canRemove)
                  InkWell(
                    onTap: onRemove,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(LucideIcons.x, size: 15, color: AppColors.mute),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: question.type,
              isDense: true,
              dropdownColor: AppColors.card,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.line),
                ),
              ),
              style: TextStyle(fontSize: 13, color: AppColors.txt),
              items: [
                for (final entry in _kTypeLabels.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (v) {
                if (v == null) return;
                question.type = v;
                onChanged();
              },
            ),
            if (question.wantsOptions) ...[
              const SizedBox(height: 8),
              for (var i = 0; i < question.optionCtrls.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: AppField(
                          controller: question.optionCtrls[i],
                          placeholder: "Option ${i + 1}",
                        ),
                      ),
                      if (question.optionCtrls.length > 1)
                        InkWell(
                          onTap: () {
                            question.optionCtrls.removeAt(i).dispose();
                            onChanged();
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Icon(LucideIcons.x, size: 14, color: AppColors.mute),
                          ),
                        ),
                    ],
                  ),
                ),
              InkWell(
                onTap: () {
                  question.optionCtrls.add(TextEditingController());
                  onChanged();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    "+ Add option",
                    style: TextStyle(fontSize: 12, color: AppColors.gold),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
