/// Mirrors one entry in `client.trainerNotes` — the coach flag/notes system.
class TrainerNote {
  const TrainerNote({
    required this.id,
    required this.flag, // "red" | "yellow" | "blue"
    this.title,
    required this.details,
    required this.coachId,
    required this.coachName,
    required this.createdAt,
    this.modifiedAt,
    this.status = "active", // "active" | "resolved" | "archived"
    this.bodyArea,
    this.followUpRequired = false,
    this.resolveBy,
  });

  final String id;
  final String flag;
  final String? title;
  final String details;
  final String coachId;
  final String coachName;
  final String createdAt;
  final String? modifiedAt;
  final String status;
  final String? bodyArea;
  final bool followUpRequired;
  final String? resolveBy;

  TrainerNote copyWith({
    String? flag,
    String? title,
    String? details,
    String? modifiedAt,
    String? status,
    String? bodyArea,
    bool? followUpRequired,
    String? resolveBy,
  }) =>
      TrainerNote(
        id: id,
        flag: flag ?? this.flag,
        title: title ?? this.title,
        details: details ?? this.details,
        coachId: coachId,
        coachName: coachName,
        createdAt: createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        status: status ?? this.status,
        bodyArea: bodyArea ?? this.bodyArea,
        followUpRequired: followUpRequired ?? this.followUpRequired,
        resolveBy: resolveBy ?? this.resolveBy,
      );
}

/// Mirrors src/constants/domain.js `BODY_AREAS`.
const kBodyAreas = [
  "Shoulder", "Elbow", "Wrist", "Neck", "Upper back", "Lower back",
  "Hip", "Knee", "Ankle", "Foot", "Full body", "Cardiovascular", "Neurological", "Other",
];
