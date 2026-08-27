import "../../data/models/client_record.dart";
import "../../data/models/program_day.dart";

class LastSetData {
  const LastSetData({this.weight = 0, this.reps = 0});
  final double weight;
  final int reps;
}

/// Mirrors programHelpers.js `getLastSetData` — most recent COMPLETED weight
/// for a given exercise + set number, scoped strictly to one workout day.
LastSetData getLastSetData(
  ClientRecord client,
  String exerciseName,
  int setNum,
  String? dayId,
) {
  var logs = client.workoutLogs.reversed.toList(); // newest first
  if (dayId != null) logs = logs.where((l) => l.dayId == dayId).toList();
  for (final log in logs) {
    final ex = log.exercises.where((e) => e.name == exerciseName);
    if (ex.isEmpty) continue;
    final set = ex.first.sets.where((s) => s.setNum == setNum && s.completed);
    if (set.isNotEmpty) {
      return LastSetData(
        weight: set.first.completedWeight ?? 0,
        reps: set.first.completedReps ?? 0,
      );
    }
  }
  return const LastSetData();
}

/// Mirrors programHelpers.js `getCurrentCycleCompletedDays` — which days in
/// the current split cycle have been logged since the last time every day
/// was completed (at which point the cycle resets and starts counting fresh).
Set<String> getCurrentCycleCompletedDays(
  ClientRecord client,
  List<ProgramDay> programDays,
) {
  final dayIds = programDays.map((d) => d.id).toList();
  if (dayIds.isEmpty) return {};
  final dayIdSet = dayIds.toSet();

  final sessions =
      client.workoutLogs
          .where((log) => dayIdSet.contains(log.dayId))
          .map((log) => (dayId: log.dayId, sortKey: log.loggedAt ?? log.date))
          .toList()
        ..sort((a, b) => a.sortKey.compareTo(b.sortKey));

  var completedThisCycle = <String>{};
  for (final s in sessions) {
    completedThisCycle.add(s.dayId);
    if (completedThisCycle.length >= dayIds.length) {
      completedThisCycle = {}; // every day hit — cycle complete, start fresh
    }
  }
  return completedThisCycle;
}

class ProgramNote {
  const ProgramNote({
    required this.label,
    required this.text,
    required this.at,
  });
  final String label;
  final String text;
  final String at;
}

/// Mirrors programHelpers.js `getClientProgramNotes`.
List<ProgramNote> getClientProgramNotes(ClientRecord client) {
  final notes = <ProgramNote>[];
  for (final prog in client.savedPrograms) {
    for (final day in prog.programDays) {
      for (final ex in day.exercises) {
        if (ex.clientNoteText != null && ex.clientNoteText!.isNotEmpty) {
          notes.add(
            ProgramNote(
              label: ex.name,
              text: ex.clientNoteText!,
              at: ex.clientNoteAt ?? "",
            ),
          );
        }
      }
    }
  }
  return notes;
}

class SetProgression {
  const SetProgression({
    required this.setNum,
    this.prevWeight,
    required this.weight,
    required this.reps,
    this.direction,
  });
  final int setNum;
  final double? prevWeight;
  final double weight;
  final int reps;
  final String?
  direction; // "up" | "down" | "same" | null (no prior set to compare)
}

class ExerciseProgression {
  const ExerciseProgression({
    required this.name,
    required this.direction,
    required this.sets,
  });
  final String name;
  final String direction; // "up" | "down" | "same" | "new"
  final List<SetProgression> sets;
}

class DayProgression {
  const DayProgression({
    required this.dayId,
    required this.dayTitle,
    required this.date,
    required this.exercises,
    required this.sourceId,
    required this.loggedBy,
  });
  final String dayId;
  final String dayTitle;
  final String date;
  final List<ExerciseProgression> exercises;
  final String sourceId;

  /// "client" (self-logged) | "coach" — see WorkoutLogEntry.loggedBy.
  final String loggedBy;
}

class _RawSession {
  _RawSession({
    required this.date,
    required this.dayId,
    required this.dayTitle,
    required this.sourceId,
    required this.exercises,
    required this.loggedBy,
  });
  final String date;
  final String dayId;
  final String dayTitle;
  final String sourceId;
  final String loggedBy;
  final List<
    ({String name, List<({int setNum, double weight, int reps})> sets})
  >
  exercises;
}

String _direction(num curr, num prev) =>
    curr > prev ? "up" : (curr < prev ? "down" : "same");

/// Mirrors programHelpers.js `getDayProgressionSummary` — compares each
/// workout day's most recent logged session against the one before it, so
/// History can show whether each exercise/set trended up, down, or held.
List<DayProgression> getDayProgressionSummary(ClientRecord client) {
  final raw = <_RawSession>[];
  for (final log in client.workoutLogs) {
    final exercises =
        <({String name, List<({int setNum, double weight, int reps})> sets})>[];
    for (final ex in log.exercises) {
      final doneSets = ex.sets
          .where((s) => s.completed)
          .map(
            (s) => (
              setNum: s.setNum,
              weight: s.completedWeight ?? 0,
              reps: s.completedReps ?? 0,
            ),
          )
          .toList();
      if (doneSets.isNotEmpty) exercises.add((name: ex.name, sets: doneSets));
    }
    raw.add(
      _RawSession(
        date: log.date,
        dayId: log.dayId,
        dayTitle: log.dayTitle,
        sourceId: log.id,
        exercises: exercises,
        loggedBy: log.loggedBy,
      ),
    );
  }
  raw.sort((a, b) => a.date.compareTo(b.date));

  final byDay = <String, List<_RawSession>>{};
  for (final session in raw) {
    byDay.putIfAbsent(session.dayId, () => []).add(session);
  }

  final days = <DayProgression>[];
  byDay.forEach((dayId, sessions) {
    if (sessions.isEmpty) return;
    final current = sessions.last;
    final previous = sessions.length > 1 ? sessions[sessions.length - 2] : null;

    final exercises = current.exercises.map((ex) {
      final prevExMatches =
          previous?.exercises.where((p) => p.name == ex.name) ??
          const Iterable.empty();
      final prevEx = prevExMatches.isNotEmpty ? prevExMatches.first : null;
      final sets = ex.sets.map((s) {
        final prevSetMatches =
            prevEx?.sets.where((p) => p.setNum == s.setNum) ??
            const Iterable.empty();
        final prevSet = prevSetMatches.isNotEmpty ? prevSetMatches.first : null;
        return SetProgression(
          setNum: s.setNum,
          prevWeight: prevSet?.weight,
          weight: s.weight,
          reps: s.reps,
          direction: prevSet != null
              ? _direction(s.weight, prevSet.weight)
              : null,
        );
      }).toList();

      String exerciseDir;
      if (sets.any((s) => s.direction == "up")) {
        exerciseDir = "up";
      } else if (sets.any((s) => s.direction == "down")) {
        exerciseDir = "down";
      } else if (sets.any((s) => s.direction == "same")) {
        exerciseDir = "same";
      } else {
        exerciseDir = "new";
      }
      return ExerciseProgression(
        name: ex.name,
        direction: exerciseDir,
        sets: sets,
      );
    }).toList();

    days.add(
      DayProgression(
        dayId: dayId,
        dayTitle: current.dayTitle,
        date: current.date,
        exercises: exercises,
        sourceId: current.sourceId,
        loggedBy: current.loggedBy,
      ),
    );
  });

  days.sort(
    (a, b) => b.date.compareTo(a.date),
  ); // most recently completed day first
  return days;
}
