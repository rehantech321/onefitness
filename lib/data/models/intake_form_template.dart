import "intake_schema.dart";

/// A gym-defined intake form, offered alongside the ones built into the app.
///
/// Until now the four assessments were a constant in code (intake_forms.dart
/// kIntakeForms), so adding a fifth — a supplement questionnaire, a return-to-
/// training screen — meant a code change and a release.
///
/// ── Why a version, rather than editing in place ─────────────────────────
/// A submitted intake is a record of what a client was asked and what they
/// said. If editing a form rewrote the questions underneath the answers
/// already on file, those answers would start rendering against questions
/// nobody was ever shown: a renamed question silently relabels last year's
/// answer, a deleted one makes an answer vanish, and a reordered scale turns
/// "7 / 10" into something else entirely.
///
/// So a template is never edited in place. Saving changes writes a new
/// version, and every version that came before stays exactly as it was,
/// readable forever. A submission records which version it was filled
/// against ([IntakeRecord.templateVersion]) and is always rendered with that
/// one. This is the same rule migration 30 applied to challenge types: a
/// finished leaderboard must not change because someone tidied up a type.
///
/// ── Why archived rather than deleted ────────────────────────────────────
/// Retiring a form stops it being offered for new submissions but leaves
/// every past one readable. A hard delete would orphan answers that clients
/// actually gave, which is the one thing this whole design exists to prevent.
class IntakeFormTemplate {
  const IntakeFormTemplate({
    required this.key,
    required this.version,
    required this.title,
    required this.sections,
    this.allowsAttachments = true,
    this.clientCanFill = true,
    this.archived = false,
    this.createdBy = "",
    this.createdAt,
  });

  /// Stable across versions — this is what a submission is filed under, and
  /// what [assessmentDefFor] looks up.
  final String key;

  /// 1 for the first save, incremented on every change. A submission names
  /// the version it was filled against.
  final int version;

  final String title;
  final List<IntakeSection> sections;
  final bool allowsAttachments;
  final bool clientCanFill;

  /// Retired: not offered for new submissions, still readable.
  final bool archived;

  final String createdBy;
  final String? createdAt;

  IntakeSchema get schema => IntakeSchema(title: title, sections: sections);

  /// How this form appears in the assessments list, so a gym-defined form and
  /// a built-in one are indistinguishable to every screen that renders them.
  AssessmentDef get asAssessment => AssessmentDef(
    key: key,
    title: title,
    by: clientCanFill ? "Client or Coach" : "Coach",
    clientCanFill: clientCanFill,
    schema: schema,
    allowsAttachments: allowsAttachments,
  );

  IntakeFormTemplate copyWith({
    String? title,
    List<IntakeSection>? sections,
    bool? allowsAttachments,
    bool? clientCanFill,
    bool? archived,
    int? version,
  }) => IntakeFormTemplate(
    key: key,
    version: version ?? this.version,
    title: title ?? this.title,
    sections: sections ?? this.sections,
    allowsAttachments: allowsAttachments ?? this.allowsAttachments,
    clientCanFill: clientCanFill ?? this.clientCanFill,
    archived: archived ?? this.archived,
    createdBy: createdBy,
    createdAt: createdAt,
  );

  static IntakeFormTemplate fromJson(Map<String, dynamic> j) {
    final schema = (j["schema"] as Map?)?.cast<String, dynamic>() ?? const {};
    return IntakeFormTemplate(
      key: j["key"] as String? ?? "",
      version: (j["version"] as num?)?.toInt() ?? 1,
      title: j["title"] as String? ?? "",
      sections: ((schema["sections"] as List?) ?? const [])
          .whereType<Map>()
          .map((s) => IntakeSection.fromJson(s.cast<String, dynamic>()))
          .toList(),
      allowsAttachments: j["allows_attachments"] as bool? ?? true,
      clientCanFill: j["client_can_fill"] as bool? ?? true,
      archived: j["archived"] as bool? ?? false,
      createdBy: j["created_by"] as String? ?? "",
      createdAt: j["created_at"]?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    "key": key,
    "version": version,
    "title": title,
    "schema": {"sections": [for (final s in sections) s.toJson()]},
    "allows_attachments": allowsAttachments,
    "client_can_fill": clientCanFill,
    "archived": archived,
    "created_by": createdBy,
  };
}
