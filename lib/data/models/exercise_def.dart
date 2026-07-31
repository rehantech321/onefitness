/// Mirrors one entry in the exercise library catalog (src/data/exercises.js),
/// trimmed to the fields the coach-facing builder/picker/editor need.
class ExerciseDef {
  const ExerciseDef({
    required this.id,
    required this.name,
    required this.movementPattern,
    required this.primaryMuscle,
    this.equipment = const [],
    this.setup,
    this.cues,
    this.coachNotes,
  });

  final String id;
  final String name;
  final String movementPattern;
  final String primaryMuscle;
  final List<String> equipment;
  final String? setup;
  final String? cues;
  final String? coachNotes;
}

/// Mirrors constants/domain.js `MOVEMENT_PATTERNS`.
const kMovementPatterns = [
  "Squat", "Hinge", "Push", "Pull", "Lunge", "Carry", "Rotation", "Isolation", "Conditioning",
];

/// Mirrors constants/domain.js muscle-group keys used by EXERCISE_LIBRARY.
const kMuscleGroups = [
  "Chest", "Back", "Shoulders", "Traps", "Biceps", "Triceps", "Forearms",
  "Quads", "Hamstrings", "Glutes", "Adductors", "Abductors", "Calves", "Core", "Cardio", "Olympic",
];
