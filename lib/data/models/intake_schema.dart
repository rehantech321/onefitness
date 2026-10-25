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
}

class IntakeSection {
  const IntakeSection({required this.title, required this.questions});
  final String title;
  final List<IntakeQuestion> questions;
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

/// One entry in client.intake — mirrors {answers, completed, at, by}, plus
/// the files attached to it.
class IntakeRecord {
  const IntakeRecord({
    this.answers = const {},
    this.completed = false,
    this.at,
    this.by,
    this.attachments = const [],
  });
  final Map<String, dynamic> answers;
  final bool completed;
  final String? at;
  final String? by;
  final List<IntakeAttachment> attachments;

  IntakeRecord copyWith({
    Map<String, dynamic>? answers,
    bool? completed,
    String? at,
    String? by,
    List<IntakeAttachment>? attachments,
  }) =>
      IntakeRecord(
        answers: answers ?? this.answers,
        completed: completed ?? this.completed,
        at: at ?? this.at,
        by: by ?? this.by,
        attachments: attachments ?? this.attachments,
      );
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
