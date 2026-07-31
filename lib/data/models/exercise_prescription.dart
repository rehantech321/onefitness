/// One exercise row inside a ProgramDay — mirrors the `exercise` shape used
/// by ExerciseSetGrid.jsx (sets/reps/weight are the coach's PRESCRIPTION;
/// actual performance is logged separately in WorkoutLogEntry).
class ExercisePrescription {
  const ExercisePrescription({
    required this.id,
    required this.name,
    this.exerciseId,
    this.group,
    this.sets = 3,
    this.reps = 0,
    this.weight,
    this.time,
    this.distance,
    this.rest,
    this.notes,
    this.laterality = "bilateral",
    this.supersetId,
    this.clientNoteText,
    this.clientNoteAt,
  });

  final String id;
  final String name;
  final String? exerciseId; // links back to the exercise catalog, null for a free-typed custom entry
  final String? group;
  final int sets;
  final int reps;
  final String? weight;
  final String? time;
  final String? distance;
  final String? rest;
  final String? notes; // coach's own cue/notes — distinct from the client's clientNoteText
  final String laterality; // "bilateral" | "unilateral"
  final String? supersetId; // shared id links consecutive exercises into a superset
  final String? clientNoteText;
  final String? clientNoteAt;

  ExercisePrescription copyWith({
    String? name,
    int? sets,
    int? reps,
    String? weight,
    String? time,
    String? distance,
    String? rest,
    String? notes,
    String? laterality,
    String? supersetId,
    bool clearSupersetId = false,
    String? clientNoteText,
    String? clientNoteAt,
    bool clearClientNote = false,
  }) =>
      ExercisePrescription(
        id: id,
        name: name ?? this.name,
        exerciseId: exerciseId,
        group: group,
        sets: sets ?? this.sets,
        reps: reps ?? this.reps,
        weight: weight ?? this.weight,
        time: time ?? this.time,
        distance: distance ?? this.distance,
        rest: rest ?? this.rest,
        notes: notes ?? this.notes,
        laterality: laterality ?? this.laterality,
        supersetId: clearSupersetId ? null : (supersetId ?? this.supersetId),
        clientNoteText: clearClientNote ? null : (clientNoteText ?? this.clientNoteText),
        clientNoteAt: clearClientNote ? null : (clientNoteAt ?? this.clientNoteAt),
      );
}
