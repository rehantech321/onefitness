/// Mirrors one set entry inside a logged exercise (ExerciseSetGrid.jsx /
/// programHelpers.js `sets`).
class LoggedSet {
  const LoggedSet({
    required this.setNum,
    this.targetReps = 0,
    this.completedReps,
    this.completedWeight,
    this.completed = false,
  });

  final int setNum;
  final int targetReps;
  final int? completedReps;
  final double? completedWeight;
  final bool completed;
}

/// One exercise's logged sets within a WorkoutLogEntry.
class LoggedExercise {
  const LoggedExercise({required this.name, this.sets = const []});

  final String name;
  final List<LoggedSet> sets;
}

/// Mirrors one entry in `client.workoutLogs` — a completed logged session.
class WorkoutLogEntry {
  const WorkoutLogEntry({
    required this.id,
    required this.date,
    required this.programId,
    required this.programName,
    required this.dayId,
    required this.dayTitle,
    this.exercises = const [],
    this.loggedAt,
  });

  final String id;
  final String date; // ISO yyyy-MM-dd
  final String programId;
  final String programName;
  final String dayId;
  final String dayTitle;
  final List<LoggedExercise> exercises;
  final String? loggedAt; // ISO datetime, used to order same-day sessions
}
