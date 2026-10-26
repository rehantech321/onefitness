import "exercise_prescription.dart";

/// Mirrors one entry in `savedProgram.programDays`.
class ProgramDay {
  const ProgramDay({
    required this.id,
    required this.title,
    this.exercises = const [],
    this.suggested = false,
    this.rationale,
  });

  final String id;
  final String title;
  final List<ExercisePrescription> exercises;

  /// A suggested active day rather than a committed gym day.
  ///
  /// Committed days are what the client signed up for — their 2, 3 or 4
  /// strength sessions. Suggested days are optional movement and conditioning
  /// shown alongside them, so a client can see what reaching their goal
  /// actually takes without it changing what they committed to. They are
  /// shorter (30-45 minutes, often a single walk or run) and are always
  /// labelled, never silently mixed in with the committed sessions.
  ///
  /// Defaults to false, which is what every program written before suggested
  /// days existed correctly reads back as.
  final bool suggested;

  /// On a suggested day, one sentence on why it earns a place for this
  /// client's goal. Null on committed days.
  final String? rationale;

  ProgramDay copyWith({List<ExercisePrescription>? exercises}) => ProgramDay(
        id: id,
        title: title,
        exercises: exercises ?? this.exercises,
        suggested: suggested,
        rationale: rationale,
      );
}
