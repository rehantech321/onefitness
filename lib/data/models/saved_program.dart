import "program_day.dart";

/// Mirrors one entry in `client.savedPrograms`.
class SavedProgram {
  const SavedProgram({
    required this.id,
    required this.name,
    this.status = "active",
    this.source,
    this.coachName,
    this.programDays = const [],
    this.createdAt,
    this.modifiedAt,
    this.assignedClientId,
    this.assignedClientName,
  });

  final String id;
  final String name;
  final String status; // "draft" | "active" | "archived"

  /// "ai" | "coach" | null — mirrors NutritionProgramEntry's own `source`.
  /// Null for anything saved before this field existed.
  final String? source;

  /// Holds the coach's display *name*, not a user id — a naming quirk
  /// carried over verbatim from SaveProgramDialog.jsx's `createdBy` field.
  final String? coachName;
  final List<ProgramDay> programDays;
  final String? createdAt;
  final String? modifiedAt;
  final String? assignedClientId;
  final String? assignedClientName;

  SavedProgram copyWith({String? name, String? status, List<ProgramDay>? programDays}) => SavedProgram(
        id: id,
        name: name ?? this.name,
        status: status ?? this.status,
        source: source,
        coachName: coachName,
        programDays: programDays ?? this.programDays,
        createdAt: createdAt,
        modifiedAt: modifiedAt,
        assignedClientId: assignedClientId,
        assignedClientName: assignedClientName,
      );
}
