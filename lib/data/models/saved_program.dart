import "program_day.dart";

/// Mirrors one entry in `client.savedPrograms`.
class SavedProgram {
  const SavedProgram({
    required this.id,
    required this.name,
    this.status = "active",
    this.coachName,
    this.programDays = const [],
  });

  final String id;
  final String name;
  final String status;
  final String? coachName;
  final List<ProgramDay> programDays;

  SavedProgram copyWith({List<ProgramDay>? programDays}) => SavedProgram(
        id: id,
        name: name,
        status: status,
        coachName: coachName,
        programDays: programDays ?? this.programDays,
      );
}
