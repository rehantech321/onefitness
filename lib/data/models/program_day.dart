import "exercise_prescription.dart";

/// Mirrors one entry in `savedProgram.programDays`.
class ProgramDay {
  const ProgramDay({required this.id, required this.title, this.exercises = const []});

  final String id;
  final String title;
  final List<ExercisePrescription> exercises;

  ProgramDay copyWith({List<ExercisePrescription>? exercises}) =>
      ProgramDay(id: id, title: title, exercises: exercises ?? this.exercises);
}
