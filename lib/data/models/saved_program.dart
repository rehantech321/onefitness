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
    this.programNote,
    this.suggestedNote,
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

  /// On an AI draft, why the split had to prioritise one muscle group over
  /// full 2x/week coverage. Written by generate-ai-workout-program only when
  /// that tradeoff was actually forced; null otherwise.
  final String? programNote;

  /// On an AI draft, why this client got the number of suggested days they
  /// did — including, importantly, why they got none. The count is decided by
  /// a fixed ladder (goal demand capped by a recovery budget), so a coach
  /// looking at a program with no suggested days can read the reason rather
  /// than assume the generator forgot.
  final String? suggestedNote;

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
        programNote: programNote,
        suggestedNote: suggestedNote,
      );
}
