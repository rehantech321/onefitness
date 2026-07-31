/// A single form field within an intake schema — mirrors the question shape
/// in src/features/intake/schemas.js.
class IntakeQuestion {
  const IntakeQuestion({
    required this.id,
    required this.label,
    required this.type, // "text" | "textarea" | "single" | "multi" | "scale"
    this.options = const [],
    this.min,
    this.max,
    this.showIfId,
    this.showIfValue,
  });

  final String id;
  final String label;
  final String type;
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

/// Mirrors TRAINING_INTAKE_SCHEMA / NUTRITION_SCHEMA — a full multi-section
/// questionnaire, rendered generically by FormFillerScreen.
class IntakeSchema {
  const IntakeSchema({required this.title, required this.sections});
  final String title;
  final List<IntakeSection> sections;
}

/// One entry in client.intake — mirrors {answers, completed, at, by}.
class IntakeRecord {
  const IntakeRecord({this.answers = const {}, this.completed = false, this.at, this.by});
  final Map<String, dynamic> answers;
  final bool completed;
  final String? at;
  final String? by;
}

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
  });

  final String key;
  final String title;
  final String by;
  final bool clientCanFill;
  final bool physical;
  final IntakeSchema? schema;
}

class IntakeFormGroup {
  const IntakeFormGroup({required this.key, required this.title, required this.assessments});
  final String key;
  final String title;
  final List<AssessmentDef> assessments;
}
