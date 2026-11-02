import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";

import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/intake_schema.dart";
import "../../../data/physical_assessment_schema.dart";

/// The coach-conducted Physical Assessment, recorded in the app.
///
/// Ported from the web app's PhysicalIntro.jsx. Until now the Flutter app
/// had no way to record one: the assessment row opened an explainer saying
/// there was nothing to fill in and to "record what you find in Notes or
/// Measurements". So the movement screen a coach runs at a client's first
/// session lived on paper, `intake.physical` was never written by this app
/// at all, and generate-ai-workout-program — which reads `scores`,
/// `painScreen`, `programmingFlags` and `coachSummary` to design around an
/// injury — always saw nothing.
///
/// Staff only. The client's side keeps the explainer: this is a screen their
/// coach performs on them, not a form they fill in.
class PhysicalAssessmentScreen extends StatefulWidget {
  const PhysicalAssessmentScreen({
    super.key,
    required this.existing,
    required this.clientName,
    required this.onBack,
    required this.onSave,
  });

  /// The previously saved assessment, so it opens as an edit rather than a
  /// blank form. Null the first time.
  final IntakeRecord? existing;

  final String clientName;
  final VoidCallback onBack;

  /// Receives the full web-shaped payload — `scores`, `observations`,
  /// `notes`, `painScreen`, `overall`, `programmingFlags`, `coachSummary`,
  /// `programStatus`, `photos` — for writing beside `completed`.
  final void Function(Map<String, dynamic> payload) onSave;

  @override
  State<PhysicalAssessmentScreen> createState() => _PhysicalAssessmentScreenState();
}

class _PhysicalAssessmentScreenState extends State<PhysicalAssessmentScreen> {
  late Map<String, String> _scores;
  late Map<String, List<String>> _observations;
  late Map<String, TextEditingController> _notes;
  late List<String> _photos;
  late List<String> _flags;
  String? _hadPain;
  String? _programStatus;

  final _painExplain = TextEditingController();
  final _primary = TextEditingController();
  final _secondary = TextEditingController();
  final _strongest = TextEditingController();
  final _summary = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final prior = widget.existing?.extra ?? const <String, dynamic>{};

    _scores = {
      for (final e in (prior["scores"] as Map?)?.entries ?? const <MapEntry<dynamic, dynamic>>[])
        if (e.value is String) "${e.key}": e.value as String,
    };
    _observations = {
      for (final e in (prior["observations"] as Map?)?.entries ?? const <MapEntry<dynamic, dynamic>>[])
        "${e.key}": ((e.value as List?) ?? const []).whereType<String>().toList(),
    };
    _notes = {
      for (final s in kPhysicalAssessmentSections)
        s.key: TextEditingController(text: ((prior["notes"] as Map?)?[s.key] as String?) ?? ""),
    };
    _photos = ((prior["photos"] as List?) ?? const []).whereType<String>().toList();
    _flags = ((prior["programmingFlags"] as List?) ?? const []).whereType<String>().toList();

    final pain = prior["painScreen"] as Map?;
    _hadPain = pain?["hadPain"] as String?;
    _painExplain.text = (pain?["explain"] as String?) ?? "";

    final overall = prior["overall"] as Map?;
    _primary.text = (overall?["primaryLimitation"] as String?) ?? "";
    _secondary.text = (overall?["secondaryLimitation"] as String?) ?? "";
    _strongest.text = (overall?["strongestPattern"] as String?) ?? "";

    _summary.text = (prior["coachSummary"] as String?) ?? "";
    _programStatus = prior["programStatus"] as String?;
  }

  @override
  void dispose() {
    for (final c in _notes.values) {
      c.dispose();
    }
    _painExplain.dispose();
    _primary.dispose();
    _secondary.dispose();
    _strongest.dispose();
    _summary.dispose();
    super.dispose();
  }

  void _toggleIn(List<String> list, String item) => setState(() {
        if (list.contains(item)) {
          list.remove(item);
        } else {
          list.add(item);
        }
      });

  void _save() {
    setState(() => _saving = true);
    widget.onSave({
      "scores": _scores,
      "observations": _observations,
      "notes": {for (final e in _notes.entries) e.key: e.value.text.trim()},
      "photos": _photos,
      // Written even when unanswered, so an assessment saved without the
      // pain screen reads as "not asked" rather than as "no pain".
      "painScreen": {"hadPain": _hadPain, "explain": _painExplain.text.trim()},
      "overall": {
        "primaryLimitation": _primary.text.trim(),
        "secondaryLimitation": _secondary.text.trim(),
        "strongestPattern": _strongest.text.trim(),
      },
      "programmingFlags": _flags,
      "coachSummary": _summary.text.trim(),
      "programStatus": _programStatus,
    });
  }

  @override
  Widget build(BuildContext context) {
    final done = widget.existing?.completed ?? false;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onBack),
          const SizedBox(height: 6),
          const Text(
            "Physical Assessment",
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            child: Text(
              done
                  ? "Recorded for ${widget.clientName}. Saving again replaces it."
                  : "Run through this with ${widget.clientName} during their first session. Rate what you see — anything left blank is simply not recorded.",
              style: TextStyle(fontSize: 12, color: AppColors.mute, height: 1.45),
            ),
          ),

          for (final section in kPhysicalAssessmentSections) ...[
            _Card(
              title: section.title,
              children: [
                if (section.photoCheck) ...[
                  const _FieldLabel("Progress photos taken"),
                  _CheckRow(
                    options: kPhysicalPhotoAngles,
                    selected: _photos,
                    onToggle: (o) => _toggleIn(_photos, o),
                  ),
                  const SizedBox(height: 16),
                ],
                for (final m in section.movements) ...[
                  _FieldLabel(m.label),
                  _GyrPills(
                    value: _scores[m.key],
                    onChanged: (v) => setState(() {
                      if (v == null) {
                        _scores.remove(m.key);
                      } else {
                        _scores[m.key] = v;
                      }
                    }),
                  ),
                  const SizedBox(height: 14),
                ],
                if (section.observations.isNotEmpty) ...[
                  const _FieldLabel("Observations"),
                  _CheckRow(
                    options: section.observations,
                    selected: _observations[section.key] ??= [],
                    onToggle: (o) => _toggleIn(_observations[section.key]!, o),
                  ),
                  const SizedBox(height: 14),
                ],
                Text("Notes", style: TextStyle(fontSize: 11, color: AppColors.mute)),
                const SizedBox(height: 5),
                AppField(controller: _notes[section.key]!, minLines: 2, maxLines: 3, placeholder: "Anything worth remembering…"),
              ],
            ),
          ],

          _Card(
            title: "Pain Screen",
            children: [
              const _FieldLabel("Did the client experience pain during any assessment movement?"),
              Row(
                children: [
                  for (final (value, label) in const [("no", "No"), ("yes", "Yes")]) ...[
                    Expanded(
                      child: _Pill(
                        label: label,
                        selected: _hadPain == value,
                        // Red for yes: it's the answer that changes the
                        // programming, so it shouldn't look like the rest.
                        color: value == "yes" ? AppColors.danger : AppColors.gold,
                        onTap: () => setState(() => _hadPain = _hadPain == value ? null : value),
                      ),
                    ),
                    if (value == "no") const SizedBox(width: 6),
                  ],
                ],
              ),
              if (_hadPain == "yes") ...[
                const SizedBox(height: 10),
                Text("If yes, explain", style: TextStyle(fontSize: 11, color: AppColors.mute)),
                const SizedBox(height: 5),
                AppField(controller: _painExplain, minLines: 2, maxLines: 3, placeholder: "Where, during which movement…"),
              ],
            ],
          ),

          _Card(
            title: "Overall Assessment",
            children: [
              Text("Primary limitation", style: TextStyle(fontSize: 11, color: AppColors.mute)),
              const SizedBox(height: 5),
              AppField(controller: _primary),
              const SizedBox(height: 12),
              Text("Secondary limitation", style: TextStyle(fontSize: 11, color: AppColors.mute)),
              const SizedBox(height: 5),
              AppField(controller: _secondary),
              const SizedBox(height: 12),
              Text("Strongest movement pattern", style: TextStyle(fontSize: 11, color: AppColors.mute)),
              const SizedBox(height: 5),
              AppField(controller: _strongest),
            ],
          ),

          _Card(
            title: "Programming Flags",
            children: [
              _CheckRow(
                options: kProgrammingFlags,
                selected: _flags,
                onToggle: (o) => _toggleIn(_flags, o),
              ),
            ],
          ),

          _Card(
            title: "Coach Summary",
            children: [
              Text(
                "Movement quality, limitations, strengths, and what it means for their programming. This is what the AI program drafter reads.",
                style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
              ),
              const SizedBox(height: 8),
              AppField(controller: _summary, minLines: 5, maxLines: 8),
            ],
          ),

          _Card(
            title: "Program Status",
            children: [
              for (final (value, label) in kProgramStatusOptions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _RadioRow(
                    label: label,
                    selected: _programStatus == value,
                    onTap: () => setState(() => _programStatus = _programStatus == value ? null : value),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 4),
          BtnGold(
            full: true,
            onPressed: _saving ? null : _save,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.check, size: 16, color: AppColors.onGold),
                const SizedBox(width: 6),
                Text(_saving ? "Saving…" : "Save assessment"),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: TextStyle(fontSize: 11, color: AppColors.gold, fontWeight: FontWeight.w800, letterSpacing: 1),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.3)),
      );
}

/// Green / Yellow / Red for one movement. Tapping the selected one clears
/// it, so a coach can un-rate a movement they rated by mistake.
class _GyrPills extends StatelessWidget {
  const _GyrPills({required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String?> onChanged;

  // A getter, not a field: see kStatusMeta in status_dot.dart.
  static List<(String, String, Color)> get _options => [
    ("green", "Green", AppColors.grn),
    // Yellow is a real yellow here. The web app had this rendering in the
    // brand green by mistake, so a coach picking "Yellow" saw a green pill.
    ("yellow", "Yellow", Color(0xFFD9A531)),
    ("red", "Red", AppColors.danger),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (key, label, color) in _options) ...[
          Expanded(
            child: _Pill(
              label: label,
              selected: value == key,
              color: color,
              onTap: () => onChanged(value == key ? null : key),
            ),
          ),
          if (key != "red") const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.color, required this.onTap});
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : AppColors.card,
          border: Border.all(color: selected ? color : AppColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: selected ? color : AppColors.mute),
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.options, required this.selected, required this.onToggle});
  final List<String> options;
  final List<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    // A chip sizes to its label, and Wrap hands children unbounded width —
    // so a long option ("Difficulty Understanding Pattern", "No Significant
    // Restrictions") grew past the screen edge and painted the overflow
    // stripe. Capping each chip at the row width lets its label wrap inside
    // the chip instead.
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxChipWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : double.infinity;
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final opt in options)
              InkWell(
                onTap: () => onToggle(opt),
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxChipWidth),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(
                      color: selected.contains(opt) ? AppColors.gold.withValues(alpha: 0.12) : AppColors.card,
                      border: Border.all(color: selected.contains(opt) ? AppColors.gold : AppColors.line),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          selected.contains(opt) ? LucideIcons.checkSquare : LucideIcons.square,
                          size: 13,
                          color: selected.contains(opt) ? AppColors.gold : AppColors.mute,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            opt,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected.contains(opt) ? AppColors.gold : AppColors.mute,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RadioRow extends StatelessWidget {
  const _RadioRow({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.gold.withValues(alpha: 0.1) : AppColors.card,
          border: Border.all(color: selected ? AppColors.gold : AppColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              selected ? LucideIcons.checkCircle2 : LucideIcons.circle,
              size: 16,
              color: selected ? AppColors.gold : AppColors.mute,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.gold : AppColors.txt,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
