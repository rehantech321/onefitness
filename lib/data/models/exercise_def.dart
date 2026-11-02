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
    this.videoPath,
    this.videoName,
  });

  final String id;
  final String name;
  final String movementPattern;
  final String primaryMuscle;
  final List<String> equipment;
  final String? setup;
  final String? cues;
  final String? coachNotes;

  /// Object name of the demo clip in the `exercise-videos` bucket, or null
  /// when nobody has filmed this exercise yet.
  ///
  /// Only the name is stored. The catalogue is loaded whole at sign-in, so a
  /// video inlined here would be downloaded by every client on every launch
  /// whether or not they ever opened it.
  final String? videoPath;

  /// The file as the coach picked it, so the editor can name what's attached
  /// instead of showing them a uuid.
  final String? videoName;

  /// True when a client has something to watch. [videoName] is cosmetic and
  /// an older record may not carry one, so it is never part of this test.
  bool get hasVideo => (videoPath ?? "").isNotEmpty;
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
