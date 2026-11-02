import "../../core/widgets/app_text_field.dart" show FieldKind;

/// A single form field within an intake schema — mirrors the question shape
/// in src/features/intake/schemas.js.
class IntakeQuestion {
  const IntakeQuestion({
    required this.id,
    required this.label,
    required this.type, // "text" | "textarea" | "single" | "multi" | "scale"
    this.inputKind,
    this.options = const [],
    this.min,
    this.max,
    this.showIfId,
    this.showIfValue,
  });

  final String id;
  final String label;
  final String type;

  /// For a "text" question, what sort of answer it takes — which decides
  /// the keyboard the client gets. An age or a phone number is still a
  /// "text" question structurally; without this it would raise the letter
  /// keyboard and the client would have to switch to digits by hand for
  /// every one of them. Null means ordinary prose.
  final FieldKind? inputKind;

  final List<String> options;
  final int? min;
  final int? max;
  final String? showIfId;
  final String? showIfValue;

  /// The question types a stored schema may use.
  ///
  /// A gym-defined form picks from these rather than inventing one: both
  /// renderers switch on [type], and a type neither recognises would render
  /// as nothing at all — a question the client never sees and the coach never
  /// knows was asked.
  static const kTypes = ["text", "textarea", "single", "multi", "scale"];

  static IntakeQuestion fromJson(Map<String, dynamic> j) {
    final type = j["type"] as String? ?? "text";
    return IntakeQuestion(
      id: j["id"] as String? ?? "",
      label: j["label"] as String? ?? "",
      // An unknown type would render as a blank, so it falls back to a plain
      // text question: the label is still asked and the answer still kept.
      type: kTypes.contains(type) ? type : "text",
      inputKind: _kindFromName(j["inputKind"] as String?),
      options: ((j["options"] as List?) ?? const [])
          .map((o) => "$o")
          .where((o) => o.isNotEmpty)
          .toList(),
      min: (j["min"] as num?)?.toInt(),
      max: (j["max"] as num?)?.toInt(),
      showIfId: j["showIfId"] as String?,
      showIfValue: j["showIfValue"] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    "id": id,
    "label": label,
    "type": type,
    if (inputKind != null) "inputKind": inputKind!.name,
    if (options.isNotEmpty) "options": options,
    if (min != null) "min": min,
    if (max != null) "max": max,
    if (showIfId != null) "showIfId": showIfId,
    if (showIfValue != null) "showIfValue": showIfValue,
  };

  static FieldKind? _kindFromName(String? name) {
    if (name == null) return null;
    for (final k in FieldKind.values) {
      if (k.name == name) return k;
    }
    return null;
  }
}

class IntakeSection {
  const IntakeSection({required this.title, required this.questions});
  final String title;
  final List<IntakeQuestion> questions;

  static IntakeSection fromJson(Map<String, dynamic> j) => IntakeSection(
    title: j["title"] as String? ?? "",
    questions: ((j["questions"] as List?) ?? const [])
        .whereType<Map>()
        .map((q) => IntakeQuestion.fromJson(q.cast<String, dynamic>()))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    "title": title,
    "questions": [for (final q in questions) q.toJson()],
  };
}

/// Whether [q] should appear, given the answers given so far. A question
/// carrying `showIf` only surfaces once its controlling answer matches —
/// for a multi-select controller, once that option is among those picked.
///
/// Lives here rather than in either renderer because both the form filler
/// and the read-only answers view have to agree: if the two drifted, a coach
/// could read back a question the client was never actually shown.
bool intakeQuestionVisible(IntakeQuestion q, Map<String, dynamic> answers) {
  if (q.showIfId == null) return true;
  final dep = answers[q.showIfId];
  if (dep is List) return dep.contains(q.showIfValue);
  return dep == q.showIfValue;
}

/// Mirrors TRAINING_INTAKE_SCHEMA / NUTRITION_SCHEMA — a full multi-section
/// questionnaire, rendered generically by FormFillerScreen.
class IntakeSchema {
  const IntakeSchema({required this.title, required this.sections});
  final String title;
  final List<IntakeSection> sections;

  static IntakeSchema fromJson(Map<String, dynamic> j) => IntakeSchema(
    title: j["title"] as String? ?? "",
    sections: ((j["sections"] as List?) ?? const [])
        .whereType<Map>()
        .map((s) => IntakeSection.fromJson(s.cast<String, dynamic>()))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    "title": title,
    "sections": [for (final s in sections) s.toJson()],
  };
}

/// A file a client attached to an intake form — bloodwork, a doctor's note,
/// a meal plan they already follow.
///
/// Only the pointer is kept here. The bytes live in the private
/// `intake-files` storage bucket, because an intake record is part of
/// `client_records.data`, which is bulk-loaded for the whole roster at
/// sign-in; inlining the files would make every coach download all of them
/// to open the app. [path] is the object name inside that bucket, and is
/// only ever exchanged for a short-lived signed URL when someone opens it.
class IntakeAttachment {
  const IntakeAttachment({
    required this.id,
    required this.name,
    required this.path,
    required this.size,
    required this.contentType,
    this.uploadedAt,
  });

  final String id;

  /// The file's original name, as the client picked it — the only label a
  /// coach has to go on, since [path] is a uuid.
  final String name;

  final String path;
  final int size;
  final String contentType; // "application/pdf" | "image/jpeg"
  final String? uploadedAt;

  bool get isPdf => contentType == "application/pdf";
  bool get isImage => contentType.startsWith("image/");
  bool get isText => contentType.startsWith("text/");

  /// Short label for the row under the file name.
  String get kindLabel => isPdf ? "PDF" : (isImage ? "Image" : (isText ? "Text" : "File"));

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "path": path,
        "size": size,
        "contentType": contentType,
        "uploadedAt": uploadedAt,
      };

  static IntakeAttachment? fromJson(Map<String, dynamic> j) {
    final path = j["path"];
    final id = j["id"];
    // A row with no path points at nothing — dropping it is better than
    // showing a file that can never open.
    if (path is! String || path.isEmpty || id is! String) return null;
    return IntakeAttachment(
      id: id,
      name: j["name"] as String? ?? "Attachment",
      path: path,
      size: (j["size"] as num?)?.toInt() ?? 0,
      contentType: j["contentType"] as String? ?? "application/pdf",
      uploadedAt: j["uploadedAt"] as String?,
    );
  }
}

/// A superseded submission of an intake form.
///
/// Filling a form again used to overwrite the answers outright: a client
/// re-doing their intake six months on, or a coach correcting a figure, left
/// no trace of what the client had said before. That history is the useful
/// part — it's how a coach sees that someone's goal moved from "fat loss" to
/// "strength", or that an injury appeared. So the answers that were there are
/// moved here instead, and [IntakeRecord] goes on holding the newest.
class IntakeSubmission {
  const IntakeSubmission({
    this.answers = const {},
    this.at,
    this.by,
    this.attachments = const [],
    this.templateVersion,
  });

  final Map<String, dynamic> answers;
  final String? at;
  final String? by;
  final List<IntakeAttachment> attachments;

  /// Which version of a gym-defined form these answers were given against.
  ///
  /// Null for the forms built into the app, whose questions live in code and
  /// change only with a release.
  final int? templateVersion;

  static IntakeSubmission fromJson(Map<String, dynamic> j) {
    final answers = j["answers"];
    return IntakeSubmission(
      answers: answers is Map ? answers.cast<String, dynamic>() : const {},
      at: j["at"] as String?,
      by: j["by"] as String?,
      templateVersion: (j["templateVersion"] as num?)?.toInt(),
      attachments: ((j["attachments"] as List?) ?? const [])
          .whereType<Map>()
          .map((a) => IntakeAttachment.fromJson(a.cast<String, dynamic>()))
          .whereType<IntakeAttachment>()
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    "answers": answers,
    "at": at,
    "by": by,
    "attachments": [for (final a in attachments) a.toJson()],
    if (templateVersion != null) "templateVersion": templateVersion,
  };
}

/// How many superseded submissions one form keeps.
///
/// Not unbounded: an intake entry lives in `client_records.data`, which is
/// bulk-loaded for the whole roster at sign-in, so every kept submission is
/// weight every coach downloads to open the app. Twenty is far more re-intakes
/// than a real client accumulates, and the attachments are only pointers.
const kMaxIntakeHistory = 20;

/// One entry in client.intake — mirrors {answers, completed, at, by}, plus
/// the files attached to it and any submissions it replaced.
class IntakeRecord {
  const IntakeRecord({
    this.answers = const {},
    this.completed = false,
    this.at,
    this.by,
    this.attachments = const [],
    this.history = const [],
    this.templateVersion,
    this.extra = const {},
  });
  final Map<String, dynamic> answers;
  final bool completed;

  /// Which version of a gym-defined form the current answers were given
  /// against; null for the forms built into the app. Read back with the
  /// matching version so a later edit to the form can't relabel, reorder or
  /// hide what the client actually answered.
  final int? templateVersion;
  final String? at;
  final String? by;
  final List<IntakeAttachment> attachments;

  /// Earlier submissions of this same form, newest first.
  ///
  /// The current answers deliberately stay on this record rather than moving
  /// into the list: everything that reads an intake — the AI program drafter,
  /// the waiver's merge tokens, the onboarding checklist, and the web app —
  /// looks at `intake[key].answers`, and none of them should have to learn
  /// about history to go on finding the latest answer.
  final List<IntakeSubmission> history;

  /// Any other top-level keys on this intake entry, carried through
  /// untouched.
  ///
  /// The physical assessment is the reason: it stores `scores`,
  /// `observations`, `painScreen`, `programmingFlags`, `coachSummary` and
  /// the rest beside `completed`, not inside `answers` — a shape the web app
  /// writes and generate-ai-workout-program reads. Without this, any save
  /// from the app rebuilt the entry from the fields it knew about and
  /// silently deleted the others, so one coach leaving a comment could wipe
  /// another's whole movement screen.
  final Map<String, dynamic> extra;

  IntakeRecord copyWith({
    Map<String, dynamic>? answers,
    bool? completed,
    String? at,
    String? by,
    List<IntakeAttachment>? attachments,
    List<IntakeSubmission>? history,
    int? templateVersion,
    Map<String, dynamic>? extra,
  }) =>
      IntakeRecord(
        answers: answers ?? this.answers,
        completed: completed ?? this.completed,
        at: at ?? this.at,
        by: by ?? this.by,
        attachments: attachments ?? this.attachments,
        history: history ?? this.history,
        templateVersion: templateVersion ?? this.templateVersion,
        extra: extra ?? this.extra,
      );

  /// [next] as the current submission, with whatever was here pushed onto the
  /// front of the history.
  ///
  /// Only a completed submission is archived: saving over a form that was
  /// never filled in — or re-saving a draft — would otherwise stack up empty
  /// entries that say nothing about the client.
  IntakeRecord supersededBy(IntakeRecord next) {
    if (!completed) return next.copyWith(history: history);
    return next.copyWith(
      history: [
        IntakeSubmission(
          answers: answers,
          at: at,
          by: by,
          attachments: attachments,
          // Travels with the answers: without it an archived submission would
          // be read back against whatever the form says today.
          templateVersion: templateVersion,
        ),
        ...history,
      ].take(kMaxIntakeHistory).toList(),
    );
  }

  /// The keys this model stores in its own fields. Everything else on an
  /// intake entry belongs in [extra].
  static const knownKeys = {
    "answers",
    "completed",
    "at",
    "by",
    "attachments",
    "history",
    "templateVersion",
  };
}

/// How many files one intake form accepts. A cap at all because these are
/// supporting documents, not an album; six because that is what was asked
/// for and it comfortably covers a full blood panel.
const kMaxIntakeAttachments = 6;

/// One row in the Assessments list — mirrors an entry in INTAKE_FORMS'
/// `assessments` array.
class AssessmentDef {
  const AssessmentDef({
    required this.key,
    required this.title,
    required this.by,
    this.clientCanFill = true,
    this.physical = false,
    this.schema,
    this.allowsAttachments = false,
  });

  final String key;
  final String title;
  final String by;
  final bool clientCanFill;
  final bool physical;
  final IntakeSchema? schema;

  /// Whether this form takes supporting files. Opt-in per assessment rather
  /// than on every form: the training intake asks about goals and injuries
  /// and has nothing to attach, while a nutrition intake routinely comes
  /// with bloodwork or a plan a client is already following.
  final bool allowsAttachments;
}

class IntakeFormGroup {
  const IntakeFormGroup({required this.key, required this.title, required this.assessments});
  final String key;
  final String title;
  final List<AssessmentDef> assessments;
}
